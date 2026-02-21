
# Sistema de Monitoramento de Equipamentos

Sistema web completo para monitoramento em tempo real de computadores e totens, com detecção automática de inatividade e gestão de manutenções.

##  Visão Geral

Sistema desenvolvido para equipes de TI monitorarem equipamentos em tempo real através de:

- **Heartbeat automático**: Equipamentos enviam sinais de vida a cada minuto
- **Detecção de inatividade**: Sistema detecta automaticamente quando um equipamento para de responder
- **Alertas em tempo real**: Notificações imediatas para a equipe técnica
- **Gestão de manutenções**: Registro completo de manutenções e histórico
- **Dashboard intuitivo**: Visualização clara do status de todos os equipamentos
- **Identificação de criticidade**: Equipamentos com problemas recorrentes são marcados automaticamente

---

##  Funcionalidades

### Para Técnicos de TI
-  Visualização de todos os equipamentos
-  Dashboard com status em tempo real
-  Registro e gestão de manutenções
-  Histórico completo de alterações
-  Alertas de equipamentos inativos
-  Identificação de equipamentos críticos
-  CRUD completo de equipamentos

### Para Usuários Comuns
-  Visualização do status da própria máquina
-  Envio automático de heartbeat

### Funcionalidades Automáticas
-  Detecção de inatividade (timeout de 5 minutos)
-  Marcação automática de equipamentos críticos (≥3 manutenções em 3 meses)
-  Atualização de status baseada em heartbeat
-  Registro de histórico de todas as alterações
-  Limpeza automática de heartbeats antigos (>90 dias)

---

##  Arquitetura

### Stack Tecnológica

**Backend:**
- Python 3.11+
- FastAPI (API REST)
- SQLAlchemy (ORM)
- PostgreSQL 14+ (Banco de dados)
- Pydantic (Validação)
- JWT (Autenticação)

**Infraestrutura:**
- Docker & Docker Compose
- Redis (Cache)
- APScheduler (Jobs agendados)
- Prometheus (Métricas)
- Nginx (Reverse proxy)

**Ferramentas:**
- Alembic (Migrations)
- pytest (Testes)
- Locust (Testes de carga)
- Black (Formatação)
- Flake8 (Linting)

### Componentes Principais

```
┌─────────────────┐
│   Equipamentos  │ → Heartbeat (1/min) → API → PostgreSQL
└─────────────────┘                        ↓
                                           ↓
                                    ┌──────────────┐
                                    │ Timeout      │
                                    │ Checker      │ → Alertas
                                    │ (Job 1/min)  │
                                    └──────────────┘
```

---

##  Instalação

### Pré-requisitos

- Python 3.11 ou superior
- PostgreSQL 14 ou superior
- Redis 7 (opcional, para cache)
- Git

### Instalação Rápida com Docker

```bash
# Clonar repositório
git clone https://github.com/empresa/monitoring-system.git
cd monitoring-system

# Configurar variáveis de ambiente
cp .env.example .env
# Editar .env com suas configurações

# Subir containers
docker-compose up -d

# Criar estrutura do banco
docker-compose exec api alembic upgrade head

# Importar dados da planilha
docker-compose exec api python scripts/import_planilha.py /data/planilha.ods
```

### Instalação Manual

```bash
# Clonar repositório
git clone https://github.com/empresa/monitoring-system.git
cd monitoring-system

# Criar ambiente virtual
python -m venv venv
source venv/bin/activate  # Linux/Mac
# ou
venv\Scripts\activate  # Windows

# Instalar dependências
pip install -r requirements.txt

# Configurar variáveis de ambiente
cp .env.example .env
# Editar .env

# Criar banco de dados
createdb monitoring
psql monitoring < 02_SCRIPT_CRIACAO_BANCO.sql

# Executar migrations
alembic upgrade head

# Importar dados da planilha
python 06_SCRIPT_IMPORTACAO.py /caminho/planilha.ods

# Iniciar servidor
uvicorn app.main:app --reload
```

---

##  Configuração

### Variáveis de Ambiente

Crie um arquivo `.env` baseado no `.env.example`:

```env
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/monitoring

# Security
SECRET_KEY=sua-chave-super-secreta-de-pelo-menos-32-caracteres
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Heartbeat
HEARTBEAT_INTERVAL=60        # Intervalo em segundos
HEARTBEAT_TIMEOUT=300        # Timeout em segundos (5 min)
CHECK_INTERVAL=60            # Frequência de verificação

# Alertas
ENABLE_ALERTS=true
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=alerts@empresa.com
SMTP_PASSWORD=senha-email
WEBHOOK_URL=https://hooks.empresa.com/alerts

# Cache (opcional)
REDIS_URL=redis://localhost:6379

# Ambiente
ENVIRONMENT=production
LOG_LEVEL=INFO
```

### Criar Usuário Administrador

```bash
python scripts/create_admin.py
```

Ou manualmente:

```sql
INSERT INTO usuarios (nome, email, senha_hash, perfil, ativo)
VALUES (
    'Admin',
    'admin@empresa.com',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIq.7FdNLO',
    'TECNICO',
    TRUE
);
```

Credenciais padrão: `admin@empresa.com` / `admin123` (trocar imediatamente)

---

##  Uso

### 1. Configurar Cliente de Heartbeat

Instale o cliente em cada equipamento:

```python
# heartbeat_client.py
import requests
import time

API_URL = "http://api.empresa.com"
ID_EQUIPAMENTO = "PC-EMB-01"  # ID único do equipamento

while True:
    try:
        response = requests.post(
            f"{API_URL}/api/v1/heartbeat",
            json={
                "id_equipamento": ID_EQUIPAMENTO,
                "ip_origem": "192.168.1.100"
            },
            timeout=5
        )
        print(f"✓ Heartbeat enviado: {response.status_code}")
    except Exception as e:
        print(f"✗ Erro: {e}")
    
    time.sleep(60)  # Aguarda 1 minuto
```

Execute como serviço (systemd no Linux):

```ini
# /etc/systemd/system/heartbeat.service
[Unit]
Description=Heartbeat Client
After=network.target

[Service]
Type=simple
User=usuario
WorkingDirectory=/opt/heartbeat
ExecStart=/usr/bin/python3 /opt/heartbeat/client.py
Restart=always

[Install]
WantedBy=multi-user.target
```

### 2. Acessar API

**Autenticação:**
```bash
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@empresa.com", "senha": "admin123"}'
```

**Listar Equipamentos:**
```bash
curl http://localhost:8000/api/v1/equipamentos \
  -H "Authorization: Bearer {seu_token}"
```

**Registrar Manutenção:**
```bash
curl -X POST http://localhost:8000/api/v1/manutencoes \
  -H "Authorization: Bearer {seu_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "equipamento_id": 1,
    "tipo_manutencao": "CORRETIVA",
    "descricao": "Substituição de memória RAM"
  }'
```

### 3. Importar Planilha

```bash
# Importação inicial (não sobrescreve)
python 06_SCRIPT_IMPORTACAO.py planilha.ods

# Atualizar dados existentes
python 06_SCRIPT_IMPORTACAO.py planilha.ods --sobrescrever
```

---

##  Documentação

Toda a documentação está organizada nos seguintes arquivos:

1. **[01_MODELO_BANCO_DADOS.md](01_MODELO_BANCO_DADOS.md)**
   - Diagrama ER completo
   - Especificação de todas as tabelas
   - Views úteis
   - Regras de negócio

2. **[02_SCRIPT_CRIACAO_BANCO.sql](02_SCRIPT_CRIACAO_BANCO.sql)**
   - Script SQL completo
   - Criação de tabelas, índices e triggers
   - Dados iniciais
   - Functions e procedures

3. **[03_API_REST_DOCUMENTACAO.md](03_API_REST_DOCUMENTACAO.md)**
   - Todos os endpoints da API
   - Exemplos de payload
   - Códigos de resposta
   - Autenticação e permissões

4. **[04_LOGICA_MONITORAMENTO.md](04_LOGICA_MONITORAMENTO.md)**
   - Como funciona o heartbeat
   - Intervalos e timeouts
   - Sistema de alertas
   - Tratamento de falhas

5. **[05_BOAS_PRATICAS.md](05_BOAS_PRATICAS.md)**
   - Segurança
   - Escalabilidade
   - Monitoramento
   - Testes
   - Deploy

6. **[06_SCRIPT_IMPORTACAO.py](06_SCRIPT_IMPORTACAO.py)**
   - Script para importar planilha
   - Validações e conversões
   - Tratamento de erros
---

##  Testes

### Executar Testes Unitários

```bash
# Todos os testes
pytest

# Com cobertura
pytest --cov=app tests/

# Testes específicos
pytest tests/test_equipamentos.py
```

### Testes de Integração

```bash
pytest tests/integration/
```

### Testes de Carga

```bash
# Instalar locust
pip install locust

# Executar
locust -f tests/load/locustfile.py --host=http://localhost:8000
```
---

##  Deploy

### Deploy com Docker Compose (Recomendado)

```bash
# Produção
docker-compose -f docker-compose.prod.yml up -d

# Verificar logs
docker-compose logs -f api

# Backup do banco
docker-compose exec db pg_dump -U user monitoring > backup.sql
```

### Deploy Manual

1. **Configurar servidor:**
```bash
# Instalar dependências
sudo apt update
sudo apt install python3.11 postgresql nginx redis-server

# Configurar PostgreSQL
sudo -u postgres createuser monitoring
sudo -u postgres createdb -O monitoring monitoring
```

2. **Deploy da aplicação:**
```bash
# Clonar e configurar
git clone https://github.com/empresa/monitoring-system.git
cd monitoring-system
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configurar .env
cp .env.example .env
nano .env

# Migrations
alembic upgrade head

# Configurar systemd
sudo cp deploy/monitoring-api.service /etc/systemd/system/
sudo systemctl enable monitoring-api
sudo systemctl start monitoring-api
```

3. **Configurar Nginx:**
```nginx
server {
    listen 80;
    server_name monitoring.empresa.com;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Monitoramento de Produção

```bash
# Verificar saúde
curl http://localhost:8000/health

# Ver métricas
curl http://localhost:8000/metrics

# Logs
tail -f logs/monitoring.log
```

---

##  Contribuição

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/NovaFuncionalidade`)
3. Commit suas mudanças (`git commit -m 'Adiciona nova funcionalidade'`)
4. Push para a branch (`git push origin feature/NovaFuncionalidade`)
5. Abra um Pull Request

### Padrões de Código

- Python: PEP 8 (use `black` e `flake8`)
- Commits: Conventional Commits
- Testes: Cobertura mínima de 80%
- Documentação: Docstrings em todas as funções

---

##  Status do Projeto

-  Modelo de banco de dados
-  API REST completa
-  Sistema de heartbeat
-  Detecção de inatividade
-  Gestão de manutenções
-  Sistema de alertas
-  Importação de planilha
-  Frontend web (em desenvolvimento)
-  App mobile (planejado)

---

##  Suporte

- **Documentação**: Consulte os arquivos `.md` na raiz do projeto

---

**Última atualização**: 2026-01-30
**Versão**: 1.0.0
