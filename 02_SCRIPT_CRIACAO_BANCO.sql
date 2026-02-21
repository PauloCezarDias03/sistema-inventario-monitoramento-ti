-- ============================================================================
-- SISTEMA DE MONITORAMENTO DE EQUIPAMENTOS
-- Script de Criação do Banco de Dados PostgreSQL 14+
-- ============================================================================
-- Autor: Sistema de Monitoramento
-- Data: 2026-01-30
-- Versão: 1.0.0
-- ============================================================================

-- Criar extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- TABELA: usuarios
-- Armazena usuários do sistema com controle de perfil
-- ============================================================================
CREATE TABLE usuarios (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    senha_hash VARCHAR(255) NOT NULL,
    perfil VARCHAR(20) NOT NULL CHECK (perfil IN ('TECNICO', 'USUARIO')),
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT email_valido CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

CREATE INDEX idx_usuarios_email ON usuarios(email);
CREATE INDEX idx_usuarios_perfil ON usuarios(perfil);
CREATE INDEX idx_usuarios_ativo ON usuarios(ativo) WHERE ativo = TRUE;

COMMENT ON TABLE usuarios IS 'Usuários do sistema com controle de acesso';
COMMENT ON COLUMN usuarios.perfil IS 'TECNICO: acesso completo | USUARIO: visualização própria máquina';
COMMENT ON COLUMN usuarios.ativo IS 'Soft delete - FALSE para desativar';

-- ============================================================================
-- TABELA: setores
-- Catálogo de setores da empresa
-- ============================================================================
CREATE TABLE setores (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) UNIQUE NOT NULL,
    abreviacao VARCHAR(10) UNIQUE NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_setores_abreviacao ON setores(abreviacao);
CREATE INDEX idx_setores_ativo ON setores(ativo) WHERE ativo = TRUE;

COMMENT ON TABLE setores IS 'Setores da empresa onde equipamentos estão alocados';

-- ============================================================================
-- TABELA: equipamentos
-- Registro central de todos os equipamentos monitorados
-- ============================================================================
CREATE TABLE equipamentos (
    id SERIAL PRIMARY KEY,
    id_equipamento VARCHAR(20) UNIQUE NOT NULL,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('COMPUTADOR', 'TOTEM')),
    setor_id INTEGER NOT NULL REFERENCES setores(id) ON DELETE RESTRICT,
    numero_fisico VARCHAR(10) NOT NULL,
    funcao VARCHAR(100),
    codigo_visual_atual VARCHAR(100),
    status_atual VARCHAR(20) NOT NULL DEFAULT 'ATIVO' 
        CHECK (status_atual IN ('ATIVO', 'INATIVO', 'EM_MANUTENCAO')),
    ultimo_heartbeat TIMESTAMP,
    critico BOOLEAN NOT NULL DEFAULT FALSE,
    observacoes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT id_equipamento_formato CHECK (id_equipamento ~ '^(PC|TOT)-[A-Z]{3}-\d{2}$')
);

CREATE INDEX idx_equipamentos_id_equipamento ON equipamentos(id_equipamento);
CREATE INDEX idx_equipamentos_setor ON equipamentos(setor_id);
CREATE INDEX idx_equipamentos_status ON equipamentos(status_atual);
CREATE INDEX idx_equipamentos_critico ON equipamentos(critico) WHERE critico = TRUE;
CREATE INDEX idx_equipamentos_tipo ON equipamentos(tipo);
CREATE INDEX idx_equipamentos_ultimo_heartbeat ON equipamentos(ultimo_heartbeat DESC NULLS LAST);

COMMENT ON TABLE equipamentos IS 'Equipamentos monitorados: computadores e totens';
COMMENT ON COLUMN equipamentos.id_equipamento IS 'ID único imutável formato: PC-EMB-01 ou TOT-USI-02';
COMMENT ON COLUMN equipamentos.status_atual IS 'Status atual do equipamento';
COMMENT ON COLUMN equipamentos.ultimo_heartbeat IS 'Timestamp do último sinal de vida recebido';
COMMENT ON COLUMN equipamentos.critico IS 'Marcado como crítico se >= 3 manutenções em 3 meses';

-- ============================================================================
-- TABELA: heartbeats
-- Registro de sinais de vida dos equipamentos (particionada)
-- ============================================================================
CREATE TABLE heartbeats (
    id BIGSERIAL,
    equipamento_id INTEGER NOT NULL REFERENCES equipamentos(id) ON DELETE CASCADE,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_origem INET,
    metadados JSONB,
    PRIMARY KEY (id, timestamp)
) PARTITION BY RANGE (timestamp);

CREATE INDEX idx_heartbeats_equipamento ON heartbeats(equipamento_id);
CREATE INDEX idx_heartbeats_timestamp ON heartbeats(timestamp DESC);
CREATE INDEX idx_heartbeats_equip_timestamp ON heartbeats(equipamento_id, timestamp DESC);

COMMENT ON TABLE heartbeats IS 'Sinais de vida dos equipamentos - particionado por mês';
COMMENT ON COLUMN heartbeats.metadados IS 'Dados adicionais em JSON (uso CPU, memória, etc)';

-- Criar partições para os próximos 3 meses
CREATE TABLE heartbeats_2026_01 PARTITION OF heartbeats
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE heartbeats_2026_02 PARTITION OF heartbeats
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE heartbeats_2026_03 PARTITION OF heartbeats
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

CREATE TABLE heartbeats_2026_04 PARTITION OF heartbeats
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');

-- ============================================================================
-- TABELA: historico_equipamentos
-- Auditoria completa de alterações nos equipamentos
-- ============================================================================
CREATE TABLE historico_equipamentos (
    id BIGSERIAL PRIMARY KEY,
    equipamento_id INTEGER NOT NULL REFERENCES equipamentos(id) ON DELETE CASCADE,
    usuario_id INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
    campo_alterado VARCHAR(50) NOT NULL,
    valor_anterior TEXT,
    valor_novo TEXT,
    tipo_alteracao VARCHAR(20) NOT NULL CHECK (tipo_alteracao IN ('CREATE', 'UPDATE', 'DELETE')),
    motivo TEXT,
    timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_historico_equipamento ON historico_equipamentos(equipamento_id, timestamp DESC);
CREATE INDEX idx_historico_usuario ON historico_equipamentos(usuario_id);
CREATE INDEX idx_historico_timestamp ON historico_equipamentos(timestamp DESC);
CREATE INDEX idx_historico_tipo_alteracao ON historico_equipamentos(tipo_alteracao);

COMMENT ON TABLE historico_equipamentos IS 'Registro imutável de todas as alterações';
COMMENT ON COLUMN historico_equipamentos.usuario_id IS 'NULL para alterações automáticas do sistema';

-- ============================================================================
-- TABELA: manutencoes
-- Registro de manutenções realizadas nos equipamentos
-- ============================================================================
CREATE TABLE manutencoes (
    id SERIAL PRIMARY KEY,
    equipamento_id INTEGER NOT NULL REFERENCES equipamentos(id) ON DELETE CASCADE,
    tecnico_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE RESTRICT,
    tipo_manutencao VARCHAR(50) NOT NULL 
        CHECK (tipo_manutencao IN ('PREVENTIVA', 'CORRETIVA', 'EMERGENCIAL')),
    descricao TEXT NOT NULL,
    data_inicio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_fim TIMESTAMP,
    resolvido BOOLEAN NOT NULL DEFAULT FALSE,
    observacoes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT data_fim_valida CHECK (data_fim IS NULL OR data_fim >= data_inicio)
);

CREATE INDEX idx_manutencoes_equipamento ON manutencoes(equipamento_id, data_inicio DESC);
CREATE INDEX idx_manutencoes_tecnico ON manutencoes(tecnico_id);
CREATE INDEX idx_manutencoes_data_inicio ON manutencoes(data_inicio DESC);
CREATE INDEX idx_manutencoes_resolvido ON manutencoes(resolvido);
CREATE INDEX idx_manutencoes_tipo ON manutencoes(tipo_manutencao);

COMMENT ON TABLE manutencoes IS 'Registro de manutenções para cálculo de criticidade';
COMMENT ON COLUMN manutencoes.tipo_manutencao IS 'PREVENTIVA | CORRETIVA | EMERGENCIAL';

-- ============================================================================
-- FUNCTIONS E TRIGGERS
-- ============================================================================

-- Função para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger de updated_at em todas as tabelas relevantes
CREATE TRIGGER set_timestamp_usuarios
    BEFORE UPDATE ON usuarios
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_timestamp_setores
    BEFORE UPDATE ON setores
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_timestamp_equipamentos
    BEFORE UPDATE ON equipamentos
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_timestamp_manutencoes
    BEFORE UPDATE ON manutencoes
    FOR EACH ROW
    EXECUTE FUNCTION trigger_set_timestamp();

-- ============================================================================
-- Função para registrar alterações no histórico
-- ============================================================================
CREATE OR REPLACE FUNCTION registrar_alteracao_equipamento()
RETURNS TRIGGER AS $$
BEGIN
    -- Registrar criação
    IF TG_OP = 'INSERT' THEN
        INSERT INTO historico_equipamentos 
            (equipamento_id, campo_alterado, valor_novo, tipo_alteracao)
        VALUES 
            (NEW.id, 'equipamento_criado', NEW.id_equipamento, 'CREATE');
        RETURN NEW;
    END IF;
    
    -- Registrar alteração de status
    IF TG_OP = 'UPDATE' AND OLD.status_atual != NEW.status_atual THEN
        INSERT INTO historico_equipamentos 
            (equipamento_id, campo_alterado, valor_anterior, valor_novo, tipo_alteracao)
        VALUES 
            (NEW.id, 'status_atual', OLD.status_atual, NEW.status_atual, 'UPDATE');
    END IF;
    
    -- Registrar alteração de setor
    IF TG_OP = 'UPDATE' AND OLD.setor_id != NEW.setor_id THEN
        INSERT INTO historico_equipamentos 
            (equipamento_id, campo_alterado, valor_anterior, valor_novo, tipo_alteracao)
        VALUES 
            (NEW.id, 'setor_id', OLD.setor_id::TEXT, NEW.setor_id::TEXT, 'UPDATE');
    END IF;
    
    -- Registrar marcação crítica
    IF TG_OP = 'UPDATE' AND OLD.critico != NEW.critico THEN
        INSERT INTO historico_equipamentos 
            (equipamento_id, campo_alterado, valor_anterior, valor_novo, tipo_alteracao)
        VALUES 
            (NEW.id, 'critico', OLD.critico::TEXT, NEW.critico::TEXT, 'UPDATE');
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_historico_equipamento
    AFTER INSERT OR UPDATE ON equipamentos
    FOR EACH ROW
    EXECUTE FUNCTION registrar_alteracao_equipamento();

-- ============================================================================
-- Função para atualizar último heartbeat
-- ============================================================================
CREATE OR REPLACE FUNCTION atualizar_ultimo_heartbeat()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE equipamentos
    SET ultimo_heartbeat = NEW.timestamp,
        status_atual = CASE 
            WHEN status_atual = 'INATIVO' THEN 'ATIVO'
            ELSE status_atual
        END
    WHERE id = NEW.equipamento_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_atualizar_heartbeat
    AFTER INSERT ON heartbeats
    FOR EACH ROW
    EXECUTE FUNCTION atualizar_ultimo_heartbeat();

-- ============================================================================
-- Função para recalcular criticidade após manutenção
-- ============================================================================
CREATE OR REPLACE FUNCTION recalcular_criticidade()
RETURNS TRIGGER AS $$
DECLARE
    qtd_manutencoes INTEGER;
BEGIN
    -- Contar manutenções nos últimos 3 meses
    SELECT COUNT(*) INTO qtd_manutencoes
    FROM manutencoes
    WHERE equipamento_id = NEW.equipamento_id
      AND data_inicio >= CURRENT_TIMESTAMP - INTERVAL '3 months';
    
    -- Marcar como crítico se >= 3 manutenções
    UPDATE equipamentos
    SET critico = (qtd_manutencoes >= 3)
    WHERE id = NEW.equipamento_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_recalcular_criticidade
    AFTER INSERT OR UPDATE ON manutencoes
    FOR EACH ROW
    EXECUTE FUNCTION recalcular_criticidade();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: Equipamentos com informações completas
CREATE OR REPLACE VIEW vw_equipamentos_completo AS
SELECT 
    e.id,
    e.id_equipamento,
    e.tipo,
    s.nome as setor_nome,
    s.abreviacao as setor_abrev,
    e.numero_fisico,
    e.funcao,
    e.codigo_visual_atual,
    e.status_atual,
    e.ultimo_heartbeat,
    e.critico,
    e.observacoes,
    CASE 
        WHEN e.ultimo_heartbeat IS NULL THEN NULL
        WHEN e.status_atual = 'EM_MANUTENCAO' THEN NULL
        ELSE EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - e.ultimo_heartbeat))::INTEGER
    END as segundos_inativo,
    CASE 
        WHEN e.ultimo_heartbeat IS NULL THEN 'Nunca conectado'
        WHEN e.status_atual = 'EM_MANUTENCAO' THEN 'Em manutenção'
        WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - e.ultimo_heartbeat)) < 300 THEN 'Online'
        WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - e.ultimo_heartbeat)) < 3600 THEN 'Inativo (< 1h)'
        WHEN EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - e.ultimo_heartbeat)) < 86400 THEN 'Inativo (< 24h)'
        ELSE 'Offline'
    END as status_descritivo
FROM equipamentos e
JOIN setores s ON e.setor_id = s.id;

-- View: Dashboard por setor
CREATE OR REPLACE VIEW vw_dashboard_setores AS
SELECT 
    s.id as setor_id,
    s.nome as setor,
    s.abreviacao,
    COUNT(e.id) as total_equipamentos,
    COUNT(e.id) FILTER (WHERE e.tipo = 'COMPUTADOR') as computadores,
    COUNT(e.id) FILTER (WHERE e.tipo = 'TOTEM') as totens,
    COUNT(e.id) FILTER (WHERE e.status_atual = 'ATIVO') as ativos,
    COUNT(e.id) FILTER (WHERE e.status_atual = 'INATIVO') as inativos,
    COUNT(e.id) FILTER (WHERE e.status_atual = 'EM_MANUTENCAO') as em_manutencao,
    COUNT(e.id) FILTER (WHERE e.critico = TRUE) as criticos
FROM setores s
LEFT JOIN equipamentos e ON s.id = e.setor_id
WHERE s.ativo = TRUE
GROUP BY s.id, s.nome, s.abreviacao
ORDER BY s.nome;

-- View: Equipamentos críticos
CREATE OR REPLACE VIEW vw_equipamentos_criticos AS
SELECT 
    e.id,
    e.id_equipamento,
    e.tipo,
    s.nome as setor,
    e.status_atual,
    COUNT(m.id) as manutencoes_3_meses,
    MAX(m.data_inicio) as ultima_manutencao,
    STRING_AGG(DISTINCT m.tipo_manutencao, ', ') as tipos_manutencao
FROM equipamentos e
JOIN setores s ON e.setor_id = s.id
LEFT JOIN manutencoes m ON e.id = m.equipamento_id 
    AND m.data_inicio >= CURRENT_TIMESTAMP - INTERVAL '3 months'
WHERE e.critico = TRUE
GROUP BY e.id, e.id_equipamento, e.tipo, s.nome, e.status_atual
ORDER BY manutencoes_3_meses DESC, ultima_manutencao DESC;

-- View: Histórico recente
CREATE OR REPLACE VIEW vw_historico_recente AS
SELECT 
    h.id,
    h.timestamp,
    e.id_equipamento,
    e.tipo as equipamento_tipo,
    s.nome as setor,
    u.nome as usuario,
    h.campo_alterado,
    h.valor_anterior,
    h.valor_novo,
    h.tipo_alteracao,
    h.motivo
FROM historico_equipamentos h
JOIN equipamentos e ON h.equipamento_id = e.id
JOIN setores s ON e.setor_id = s.id
LEFT JOIN usuarios u ON h.usuario_id = u.id
ORDER BY h.timestamp DESC
LIMIT 100;

-- ============================================================================
-- DADOS INICIAIS
-- ============================================================================

-- Inserir setores
INSERT INTO setores (nome, abreviacao) VALUES
    ('Embalagem', 'EMB'),
    ('Expedição/Recebimento', 'EXP'),
    ('Montagem', 'MON'),
    ('Usinagem', 'USI'),
    ('Solda', 'SOL'),
    ('Sopro/Injetora', 'SOP');

-- Inserir usuário administrador padrão (senha: admin123)
-- Hash bcrypt de 'admin123'
INSERT INTO usuarios (nome, email, senha_hash, perfil) VALUES
    ('Administrador', 'admin@empresa.com', 
     '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIq.7FdNLO', 
     'TECNICO');

-- ============================================================================
-- FUNÇÃO DE LIMPEZA DE HEARTBEATS ANTIGOS
-- ============================================================================
CREATE OR REPLACE FUNCTION limpar_heartbeats_antigos()
RETURNS INTEGER AS $$
DECLARE
    linhas_deletadas INTEGER;
BEGIN
    DELETE FROM heartbeats
    WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '90 days';
    
    GET DIAGNOSTICS linhas_deletadas = ROW_COUNT;
    RETURN linhas_deletadas;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION limpar_heartbeats_antigos IS 'Remove heartbeats com mais de 90 dias - executar via cron job';

-- ============================================================================
-- GRANTS E PERMISSÕES
-- ============================================================================

-- Role para técnicos (full access)
CREATE ROLE tecnico_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO tecnico_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO tecnico_role;

-- Role para usuários comuns (read-only limitado)
CREATE ROLE usuario_role;
GRANT SELECT ON vw_equipamentos_completo TO usuario_role;
GRANT SELECT ON equipamentos TO usuario_role;

-- ============================================================================
-- FIM DO SCRIPT
-- ============================================================================

-- Verificação final
DO $$
BEGIN
    RAISE NOTICE '✓ Banco de dados criado com sucesso!';
    RAISE NOTICE '✓ Tabelas criadas: 6';
    RAISE NOTICE '✓ Views criadas: 4';
    RAISE NOTICE '✓ Triggers criados: 7';
    RAISE NOTICE '✓ Setores inseridos: 6';
    RAISE NOTICE '✓ Sistema pronto para uso';
END $$;
