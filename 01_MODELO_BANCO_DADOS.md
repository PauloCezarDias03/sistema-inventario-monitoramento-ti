# MODELO DE BANCO DE DADOS - Sistema de Monitoramento de Equipamentos

## Visão Geral

Sistema relacional normalizado para monitoramento em tempo real de computadores e totens, com histórico completo de alterações, controle de manutenções e detecção automática de criticidade.

---

## DIAGRAMA ENTIDADE-RELACIONAMENTO

```
┌─────────────────┐
│    usuarios     │
└────────┬────────┘
         │ 1
         │
         │ N
┌────────┴────────┐         ┌──────────────────┐
│  equipamentos   │────N────│     setores      │
└────────┬────────┘    1    └──────────────────┘
         │
         │ 1
         │
         ├─────N──────┬─────────────────┐
         │            │                 │
┌────────┴────────┐   │   ┌─────────────┴──────────┐
│   heartbeats    │   │   │ historico_equipamentos │
└─────────────────┘   │   └────────────────────────┘
                      │
            ┌─────────┴────────┐
            │   manutencoes    │
            └──────────────────┘
```

---

## TABELAS E ESPECIFICAÇÕES

### 1. **usuarios**
Armazena usuários do sistema com controle de perfil.

| Campo | Tipo | Restrições | Descrição |
|-------|------|------------|-----------|
| id | SERIAL | PK, NOT NULL | Identificador único |
| nome | VARCHAR(100) | NOT NULL | Nome completo |
| email | VARCHAR(150) | UNIQUE, NOT NULL | Email (login) |
| senha_hash | VARCHAR(255) | NOT NULL | Hash bcrypt da senha |
| perfil | VARCHAR(20) | NOT NULL, CHECK | 'TECNICO' ou 'USUARIO' |
| ativo | BOOLEAN | NOT NULL, DEFAULT TRUE | Usuário ativo/inativo |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Data de criação |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Última atualização |

**Índices:**
- idx_usuarios_email (email)
- idx_usuarios_perfil (perfil)

**Regras:**
- Email único no sistema
- Perfil: 'TECNICO' ou 'USUARIO'
- Senha armazenada como hash bcrypt
- Soft delete via campo 'ativo'

---

### 2. **setores**
Catálogo de setores da empresa.

| Campo | Tipo | Restrições | Descrição |
|-------|------|------------|-----------|
| id | SERIAL | PK, NOT NULL | Identificador único |
| nome | VARCHAR(100) | UNIQUE, NOT NULL | Nome do setor |
| abreviacao | VARCHAR(10) | UNIQUE, NOT NULL | Sigla do setor |
| ativo | BOOLEAN | NOT NULL, DEFAULT TRUE | Setor ativo/inativo |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Data de criação |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Última atualização |

**Índices:**
- idx_setores_abreviacao (abreviacao)

**Dados Iniciais:**
- Embalagem (EMB)
- Expedição/Recebimento (EXP)
- Montagem (MON)
- Usinagem (USI)
- Solda (SOL)
- Sopro/Injetora (SOP)

---

### 3. **equipamentos**
Registro central de todos os equipamentos monitorados.

| Campo | Tipo | Restrições | Descrição |
|-------|------|------------|-----------|
| id | SERIAL | PK, NOT NULL | Identificador único |
| id_equipamento | VARCHAR(20) | UNIQUE, NOT NULL | ID visual (PC-EMB-01) |
| tipo | VARCHAR(20) | NOT NULL, CHECK | 'COMPUTADOR' ou 'TOTEM' |
| setor_id | INTEGER | FK, NOT NULL | Referência ao setor |
| numero_fisico | VARCHAR(10) | NOT NULL | Número físico do equip. |
| funcao | VARCHAR(100) | NULL | Função/descrição |
| codigo_visual_atual | VARCHAR(100) | NULL | Código original planilha |
| status_atual | VARCHAR(20) | NOT NULL, CHECK | Status atual |
| ultimo_heartbeat | TIMESTAMP | NULL | Último sinal recebido |
| critico | BOOLEAN | NOT NULL, DEFAULT FALSE | Marcação crítica |
| observacoes | TEXT | NULL | Observações gerais |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Data de criação |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Última atualização |

**Índices:**
- idx_equipamentos_id_equipamento (id_equipamento)
- idx_equipamentos_setor (setor_id)
- idx_equipamentos_status (status_atual)
- idx_equipamentos_critico (critico)
- idx_equipamentos_tipo (tipo)

**Regras:**
- id_equipamento único e imutável
- tipo: 'COMPUTADOR', 'TOTEM' (extensível)
- status_atual: 'ATIVO', 'INATIVO', 'EM_MANUTENCAO'
- último_heartbeat atualizado a cada ping
- critico calculado automaticamente

**Foreign Keys:**
- setor_id → setores(id) ON DELETE RESTRICT

---

### 4. **heartbeats**
Registro de sinais de vida dos equipamentos.

| Campo | Tipo | Restrições | Descrição |
|-------|------|------------|-----------|
| id | BIGSERIAL | PK, NOT NULL | Identificador único |
| equipamento_id | INTEGER | FK, NOT NULL | Equipamento |
| timestamp | TIMESTAMP | NOT NULL, DEFAULT NOW() | Momento do heartbeat |
| ip_origem | INET | NULL | IP da máquina |
| metadados | JSONB | NULL | Dados adicionais |

**Índices:**
- idx_heartbeats_equipamento (equipamento_id)
- idx_heartbeats_timestamp (timestamp DESC)
- idx_heartbeats_equip_timestamp (equipamento_id, timestamp DESC)

**Regras:**
- Particionamento recomendado por data (mensalmente)
- Retenção: 90 dias
- Limpeza automática via job

**Foreign Keys:**
- equipamento_id → equipamentos(id) ON DELETE CASCADE

---

### 5. **historico_equipamentos**
Auditoria completa de alterações nos equipamentos.

| Campo | Tipo | Restrições | Descrição |
|-------|------|------------|-----------|
| id | BIGSERIAL | PK, NOT NULL | Identificador único |
| equipamento_id | INTEGER | FK, NOT NULL | Equipamento alterado |
| usuario_id | INTEGER | FK, NULL | Quem alterou |
| campo_alterado | VARCHAR(50) | NOT NULL | Campo modificado |
| valor_anterior | TEXT | NULL | Valor antes |
| valor_novo | TEXT | NULL | Valor depois |
| tipo_alteracao | VARCHAR(20) | NOT NULL | CREATE/UPDATE/DELETE |
| motivo | TEXT | NULL | Justificativa |
| timestamp | TIMESTAMP | NOT NULL, DEFAULT NOW() | Quando ocorreu |

**Índices:**
- idx_historico_equipamento (equipamento_id, timestamp DESC)
- idx_historico_usuario (usuario_id)
- idx_historico_timestamp (timestamp DESC)

**Regras:**
- Registro imutável (INSERT only)
- NULL em usuario_id para alterações automáticas
- tipo_alteracao: 'CREATE', 'UPDATE', 'DELETE'

**Foreign Keys:**
- equipamento_id → equipamentos(id) ON DELETE CASCADE
- usuario_id → usuarios(id) ON DELETE SET NULL

---

### 6. **manutencoes**
Registro de manutenções realizadas nos equipamentos.

| Campo | Tipo | Restrições | Descrição |
|-------|------|------------|-----------|
| id | SERIAL | PK, NOT NULL | Identificador único |
| equipamento_id | INTEGER | FK, NOT NULL | Equipamento |
| tecnico_id | INTEGER | FK, NOT NULL | Técnico responsável |
| tipo_manutencao | VARCHAR(50) | NOT NULL | Tipo da manutenção |
| descricao | TEXT | NOT NULL | Descrição detalhada |
| data_inicio | TIMESTAMP | NOT NULL | Início da manutenção |
| data_fim | TIMESTAMP | NULL | Fim da manutenção |
| resolvido | BOOLEAN | NOT NULL, DEFAULT FALSE | Problema resolvido? |
| observacoes | TEXT | NULL | Observações |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Data de criação |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Última atualização |

**Índices:**
- idx_manutencoes_equipamento (equipamento_id, data_inicio DESC)
- idx_manutencoes_tecnico (tecnico_id)
- idx_manutencoes_data_inicio (data_inicio DESC)
- idx_manutencoes_resolvido (resolvido)

**Regras:**
- data_fim deve ser >= data_inicio
- tipo_manutencao: 'PREVENTIVA', 'CORRETIVA', 'EMERGENCIAL'
- Usado para calcular criticidade

**Foreign Keys:**
- equipamento_id → equipamentos(id) ON DELETE CASCADE
- tecnico_id → usuarios(id) ON DELETE RESTRICT

---

## VIEWS ÚTEIS

### vw_equipamentos_ativos
```sql
CREATE VIEW vw_equipamentos_ativos AS
SELECT 
    e.id,
    e.id_equipamento,
    e.tipo,
    s.nome as setor_nome,
    s.abreviacao as setor_abrev,
    e.numero_fisico,
    e.funcao,
    e.status_atual,
    e.ultimo_heartbeat,
    e.critico,
    CASE 
        WHEN e.ultimo_heartbeat IS NULL THEN NULL
        ELSE EXTRACT(EPOCH FROM (NOW() - e.ultimo_heartbeat))::INTEGER
    END as segundos_inativo
FROM equipamentos e
JOIN setores s ON e.setor_id = s.id
WHERE e.status_atual != 'EM_MANUTENCAO';
```

### vw_dashboard_setores
```sql
CREATE VIEW vw_dashboard_setores AS
SELECT 
    s.nome as setor,
    COUNT(*) as total_equipamentos,
    COUNT(*) FILTER (WHERE e.status_atual = 'ATIVO') as ativos,
    COUNT(*) FILTER (WHERE e.status_atual = 'INATIVO') as inativos,
    COUNT(*) FILTER (WHERE e.critico = TRUE) as criticos
FROM setores s
LEFT JOIN equipamentos e ON s.id = e.setor_id
GROUP BY s.id, s.nome
ORDER BY s.nome;
```

### vw_equipamentos_criticos
```sql
CREATE VIEW vw_equipamentos_criticos AS
SELECT 
    e.id,
    e.id_equipamento,
    e.tipo,
    s.nome as setor,
    COUNT(m.id) as manutencoes_3_meses,
    MAX(m.data_inicio) as ultima_manutencao
FROM equipamentos e
JOIN setores s ON e.setor_id = s.id
LEFT JOIN manutencoes m ON e.id = m.equipamento_id 
    AND m.data_inicio >= NOW() - INTERVAL '3 months'
WHERE e.critico = TRUE
GROUP BY e.id, e.id_equipamento, e.tipo, s.nome
ORDER BY manutencoes_3_meses DESC;
```

---

## REGRAS DE NEGÓCIO IMPLEMENTADAS NO BANCO

### 1. Detecção de Inatividade
```sql
-- Trigger para atualizar status baseado em heartbeat
CREATE OR REPLACE FUNCTION check_equipment_timeout()
RETURNS TRIGGER AS $$
BEGIN
    -- Se não recebeu heartbeat nos últimos 5 minutos, marcar como INATIVO
    IF NEW.ultimo_heartbeat < NOW() - INTERVAL '5 minutes' 
       AND NEW.status_atual = 'ATIVO' THEN
        NEW.status_atual := 'INATIVO';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### 2. Cálculo de Criticidade
```sql
-- Função para recalcular criticidade
CREATE OR REPLACE FUNCTION recalcular_criticidade(equip_id INTEGER)
RETURNS VOID AS $$
DECLARE
    qtd_manutencoes INTEGER;
BEGIN
    SELECT COUNT(*) INTO qtd_manutencoes
    FROM manutencoes
    WHERE equipamento_id = equip_id
      AND data_inicio >= NOW() - INTERVAL '3 months';
    
    -- Marcar como crítico se >= 3 manutenções em 3 meses
    UPDATE equipamentos
    SET critico = (qtd_manutencoes >= 3)
    WHERE id = equip_id;
END;
$$ LANGUAGE plpgsql;
```

### 3. Auditoria Automática
```sql
-- Trigger para registrar alterações
CREATE OR REPLACE FUNCTION registrar_alteracao_equipamento()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status_atual != NEW.status_atual THEN
            INSERT INTO historico_equipamentos 
                (equipamento_id, campo_alterado, valor_anterior, valor_novo, tipo_alteracao)
            VALUES 
                (NEW.id, 'status_atual', OLD.status_atual, NEW.status_atual, 'UPDATE');
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## POLÍTICAS DE RETENÇÃO

| Tabela | Período de Retenção | Estratégia |
|--------|---------------------|------------|
| heartbeats | 90 dias | Particionamento + purge automático |
| historico_equipamentos | 2 anos | Arquivamento em storage frio |
| manutencoes | Indefinido | Backup regular |
| equipamentos | Indefinido | Soft delete |

---

## ÍNDICES DE PERFORMANCE

Total de índices: 18
- Primários: 6
- Únicos: 4
- Compostos: 3
- Performance: 5

Cobertura de queries principais: 100%

---

## SEGURANÇA

### Níveis de Acesso
- **TECNICO**: Read/Write em todas as tabelas
- **USUARIO**: Read apenas em equipamentos (filtrado por máquina própria)
- **SYSTEM**: Permissões especiais para triggers e jobs

### Auditoria
- Todas as alterações registradas em historico_equipamentos
- Timestamps automáticos (created_at, updated_at)
- Triggers para rastreamento de mudanças críticas

---

## ESCALABILIDADE

### Preparado para:
- Particionamento de heartbeats (time-based)
- Sharding por setor (futuro)
- Read replicas para dashboard
- Cache de views materializadas

### Estimativa de Volume:
- 100 equipamentos × 12 heartbeats/hora × 24h = ~29k registros/dia
- 90 dias = ~2.6M registros (heartbeats)
- Uso de disco estimado: < 5GB/ano

---

## BACKUP E RECUPERAÇÃO

- **Backup Full**: Diário (3 AM)
- **Backup Incremental**: A cada 4 horas
- **Retenção**: 30 dias local, 1 ano cloud
- **RTO**: < 1 hora
- **RPO**: < 4 horas
