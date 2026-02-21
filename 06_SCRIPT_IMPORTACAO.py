#!/usr/bin/env python3
"""
Script de Importação de Planilha - Sistema de Monitoramento

Importa dados da planilha Mapa_Comp_totens_atualizado.ods para o banco de dados PostgreSQL.

Uso:
    python scripts/import_planilha.py /caminho/para/planilha.ods

Funcionalidades:
- Lê dados da aba 'Inventario_Equipamentos'
- Verifica setores existentes ou cria novos
- Cria equipamentos com validação
- Registra histórico de criação
- Suporta execução idempotente (não duplica dados)
"""

import sys
import os
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.exc import IntegrityError

# Adicionar diretório raiz ao path
sys.path.insert(0, str(Path(__file__).parent.parent))

# Configurações do banco
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/monitoring"
)


class ImportadorPlanilha:
    """Importa dados da planilha para o banco de dados"""
    
    def __init__(self, database_url: str):
        self.engine = create_engine(database_url)
        self.Session = sessionmaker(bind=self.engine)
        self.estatisticas = {
            'setores_criados': 0,
            'setores_existentes': 0,
            'equipamentos_criados': 0,
            'equipamentos_atualizados': 0,
            'equipamentos_ignorados': 0,
            'erros': []
        }
    
    def importar(self, arquivo_path: str, sobrescrever: bool = False):
        """
        Importa dados da planilha.
        
        Args:
            arquivo_path: Caminho para o arquivo ODS/XLSX
            sobrescrever: Se True, atualiza equipamentos existentes
        """
        print(f"🔄 Iniciando importação de: {arquivo_path}")
        print(f"📅 Data/Hora: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 80)
        
        # Validar arquivo
        if not os.path.exists(arquivo_path):
            raise FileNotFoundError(f"Arquivo não encontrado: {arquivo_path}")
        
        # Detectar extensão
        extensao = Path(arquivo_path).suffix.lower()
        engine_map = {
            '.ods': 'odf',
            '.xlsx': 'openpyxl',
            '.xls': 'xlrd'
        }
        
        if extensao not in engine_map:
            raise ValueError(f"Formato não suportado: {extensao}")
        
        # Ler planilha
        print(f"📖 Lendo planilha ({extensao})...")
        try:
            df = pd.read_excel(
                arquivo_path,
                sheet_name='Inventario_Equipamentos',
                engine=engine_map[extensao]
            )
        except Exception as e:
            raise ValueError(f"Erro ao ler planilha: {e}")
        
        print(f"✓ {len(df)} linhas encontradas")
        print()
        
        # Processar dados
        session = self.Session()
        try:
            self._processar_dados(session, df, sobrescrever)
            session.commit()
            print("\n✓ Importação concluída com sucesso!")
        except Exception as e:
            session.rollback()
            print(f"\n❌ Erro durante importação: {e}")
            raise
        finally:
            session.close()
        
        # Exibir estatísticas
        self._exibir_estatisticas()
    
    def _processar_dados(self, session: Session, df: pd.DataFrame, sobrescrever: bool):
        """Processa e importa os dados"""
        
        # 1. Processar setores
        print("📂 Processando setores...")
        setores_map = self._processar_setores(session, df)
        print(f"✓ {len(setores_map)} setores processados")
        print()
        
        # 2. Processar equipamentos
        print("🖥️  Processando equipamentos...")
        self._processar_equipamentos(session, df, setores_map, sobrescrever)
        print(f"✓ Equipamentos processados")
    
    def _processar_setores(self, session: Session, df: pd.DataFrame) -> Dict[str, int]:
        """
        Processa setores da planilha.
        
        Returns:
            Dicionário {nome_setor: id_setor}
        """
        setores_map = {}
        setores_unicos = df['Setor'].unique()
        
        for nome_setor in setores_unicos:
            if pd.isna(nome_setor):
                continue
            
            nome_setor = str(nome_setor).strip()
            
            # Gerar abreviação
            abreviacao = self._gerar_abreviacao(nome_setor)
            
            # Verificar se setor já existe
            result = session.execute(
                text("SELECT id FROM setores WHERE nome = :nome"),
                {"nome": nome_setor}
            ).fetchone()
            
            if result:
                setor_id = result[0]
                setores_map[nome_setor] = setor_id
                self.estatisticas['setores_existentes'] += 1
                print(f"  ✓ Setor existente: {nome_setor} ({abreviacao}) [ID: {setor_id}]")
            else:
                # Criar novo setor
                result = session.execute(
                    text("""
                        INSERT INTO setores (nome, abreviacao, ativo, created_at, updated_at)
                        VALUES (:nome, :abrev, TRUE, NOW(), NOW())
                        RETURNING id
                    """),
                    {"nome": nome_setor, "abrev": abreviacao}
                )
                setor_id = result.fetchone()[0]
                setores_map[nome_setor] = setor_id
                self.estatisticas['setores_criados'] += 1
                print(f"  ✓ Novo setor criado: {nome_setor} ({abreviacao}) [ID: {setor_id}]")
        
        return setores_map
    
    def _processar_equipamentos(
        self,
        session: Session,
        df: pd.DataFrame,
        setores_map: Dict[str, int],
        sobrescrever: bool
    ):
        """Processa equipamentos da planilha"""
        
        for idx, row in df.iterrows():
            try:
                self._processar_equipamento(session, row, setores_map, sobrescrever)
            except Exception as e:
                erro_msg = f"Linha {idx + 2}: {str(e)}"
                self.estatisticas['erros'].append(erro_msg)
                print(f"  ⚠️  {erro_msg}")
    
    def _processar_equipamento(
        self,
        session: Session,
        row: pd.Series,
        setores_map: Dict[str, int],
        sobrescrever: bool
    ):
        """Processa um equipamento individual"""
        
        # Extrair dados
        id_equipamento = str(row['ID_Equipamento']).strip()
        tipo = str(row['Tipo']).strip().upper()
        setor_nome = str(row['Setor']).strip()
        numero_fisico = str(row['Numero']).strip().zfill(2)
        funcao = str(row['Funcao']).strip() if pd.notna(row['Funcao']) else None
        codigo_visual = str(row['Codigo_Visual_Atual']).strip() if pd.notna(row['Codigo_Visual_Atual']) else None
        status = str(row['Status']).strip().upper() if pd.notna(row['Status']) else 'ATIVO'
        observacoes = str(row['Observacoes']).strip() if pd.notna(row['Observacoes']) else None
        
        # Validar tipo
        if tipo not in ['COMPUTADOR', 'TOTEM']:
            raise ValueError(f"Tipo inválido: {tipo}")
        
        # Validar status
        if status not in ['ATIVO', 'INATIVO', 'EM_MANUTENCAO']:
            status = 'ATIVO'  # Default
        
        # Buscar setor_id
        setor_id = setores_map.get(setor_nome)
        if not setor_id:
            raise ValueError(f"Setor não encontrado: {setor_nome}")
        
        # Verificar se equipamento já existe
        result = session.execute(
            text("SELECT id FROM equipamentos WHERE id_equipamento = :id_eq"),
            {"id_eq": id_equipamento}
        ).fetchone()
        
        if result:
            equipamento_id = result[0]
            
            if sobrescrever:
                # Atualizar equipamento existente
                session.execute(
                    text("""
                        UPDATE equipamentos
                        SET tipo = :tipo,
                            setor_id = :setor_id,
                            numero_fisico = :num,
                            funcao = :funcao,
                            codigo_visual_atual = :codigo,
                            status_atual = :status,
                            observacoes = :obs,
                            updated_at = NOW()
                        WHERE id = :id
                    """),
                    {
                        "tipo": tipo,
                        "setor_id": setor_id,
                        "num": numero_fisico,
                        "funcao": funcao,
                        "codigo": codigo_visual,
                        "status": status,
                        "obs": observacoes,
                        "id": equipamento_id
                    }
                )
                self.estatisticas['equipamentos_atualizados'] += 1
                print(f"  ↻ Atualizado: {id_equipamento}")
            else:
                # Ignorar equipamento existente
                self.estatisticas['equipamentos_ignorados'] += 1
                print(f"  - Ignorado (já existe): {id_equipamento}")
        else:
            # Criar novo equipamento
            result = session.execute(
                text("""
                    INSERT INTO equipamentos (
                        id_equipamento, tipo, setor_id, numero_fisico,
                        funcao, codigo_visual_atual, status_atual,
                        observacoes, critico, created_at, updated_at
                    )
                    VALUES (
                        :id_eq, :tipo, :setor_id, :num,
                        :funcao, :codigo, :status,
                        :obs, FALSE, NOW(), NOW()
                    )
                    RETURNING id
                """),
                {
                    "id_eq": id_equipamento,
                    "tipo": tipo,
                    "setor_id": setor_id,
                    "num": numero_fisico,
                    "funcao": funcao,
                    "codigo": codigo_visual,
                    "status": status,
                    "obs": observacoes
                }
            )
            equipamento_id = result.fetchone()[0]
            self.estatisticas['equipamentos_criados'] += 1
            print(f"  + Criado: {id_equipamento} ({tipo})")
    
    def _gerar_abreviacao(self, nome_setor: str) -> str:
        """Gera abreviação de 3 letras para o setor"""
        
        # Mapeamento manual para setores conhecidos
        mapa_setores = {
            'Embalagem': 'EMB',
            'Expedição/Recebimento': 'EXP',
            'Montagem': 'MON',
            'Usinagem': 'USI',
            'Solda': 'SOL',
            'Sopro/Injetora': 'SOP'
        }
        
        if nome_setor in mapa_setores:
            return mapa_setores[nome_setor]
        
        # Geração automática
        # Remove caracteres especiais
        nome_limpo = re.sub(r'[^a-zA-Z\s]', '', nome_setor)
        
        # Pega primeiras letras das palavras
        palavras = nome_limpo.split()
        if len(palavras) >= 3:
            abrev = ''.join([p[0].upper() for p in palavras[:3]])
        elif len(palavras) == 2:
            abrev = palavras[0][:2].upper() + palavras[1][0].upper()
        else:
            abrev = nome_limpo[:3].upper()
        
        return abrev
    
    def _exibir_estatisticas(self):
        """Exibe estatísticas da importação"""
        
        print("\n" + "=" * 80)
        print("📊 ESTATÍSTICAS DA IMPORTAÇÃO")
        print("=" * 80)
        
        print("\n🏢 SETORES:")
        print(f"  • Criados: {self.estatisticas['setores_criados']}")
        print(f"  • Existentes: {self.estatisticas['setores_existentes']}")
        
        print("\n🖥️  EQUIPAMENTOS:")
        print(f"  • Criados: {self.estatisticas['equipamentos_criados']}")
        print(f"  • Atualizados: {self.estatisticas['equipamentos_atualizados']}")
        print(f"  • Ignorados: {self.estatisticas['equipamentos_ignorados']}")
        
        total = (
            self.estatisticas['equipamentos_criados'] +
            self.estatisticas['equipamentos_atualizados'] +
            self.estatisticas['equipamentos_ignorados']
        )
        print(f"  • Total processado: {total}")
        
        if self.estatisticas['erros']:
            print(f"\n⚠️  ERROS ({len(self.estatisticas['erros'])}):")
            for erro in self.estatisticas['erros']:
                print(f"  • {erro}")
        
        print("\n" + "=" * 80)


def main():
    """Função principal"""
    
    print("""
╔═══════════════════════════════════════════════════════════════════════════╗
║                  IMPORTADOR DE PLANILHA - SISTEMA DE MONITORAMENTO        ║
╚═══════════════════════════════════════════════════════════════════════════╝
    """)
    
    # Validar argumentos
    if len(sys.argv) < 2:
        print("❌ Erro: Arquivo de planilha não especificado")
        print("\nUso:")
        print("  python scripts/import_planilha.py <arquivo.ods|xlsx>")
        print("\nOpções:")
        print("  --sobrescrever    Atualiza equipamentos existentes")
        print("\nExemplo:")
        print("  python scripts/import_planilha.py planilha.ods")
        print("  python scripts/import_planilha.py planilha.xlsx --sobrescrever")
        sys.exit(1)
    
    arquivo_path = sys.argv[1]
    sobrescrever = '--sobrescrever' in sys.argv
    
    # Validar conexão com banco
    print("🔌 Testando conexão com banco de dados...")
    try:
        engine = create_engine(DATABASE_URL)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("✓ Conexão estabelecida com sucesso")
        print(f"✓ Database: {DATABASE_URL.split('@')[-1]}")
        print()
    except Exception as e:
        print(f"❌ Erro ao conectar ao banco: {e}")
        print("\nVerifique:")
        print("  1. PostgreSQL está rodando")
        print("  2. DATABASE_URL está configurada corretamente")
        print("  3. Usuário tem permissões adequadas")
        sys.exit(1)
    
    # Executar importação
    try:
        importador = ImportadorPlanilha(DATABASE_URL)
        importador.importar(arquivo_path, sobrescrever)
        
        print("\n✅ Importação finalizada!")
        sys.exit(0)
        
    except Exception as e:
        print(f"\n❌ Erro crítico: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
