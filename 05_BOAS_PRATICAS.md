# BOAS PRÁTICAS - Sistema de Monitoramento de Equipamentos

## 1. SEGURANÇA

### 1.1 Autenticação e Autorização

#### Senha Segura
```python
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_senha(senha: str) -> str:
    """Hash de senha usando bcrypt"""
    return pwd_context.hash(senha)

def verificar_senha(senha_plain: str, senha_hash: str) -> bool:
    """Verifica senha contra hash"""
    return pwd_context.verify(senha_plain, senha_hash)
```

**Regras:**
- Mínimo 8 caracteres
- Pelo menos 1 letra maiúscula
- Pelo menos 1 número
- Pelo menos 1 caractere especial
- Não reutilizar últimas 5 senhas
- Expiração a cada 90 dias (opcional)

#### JWT Token
```python
from datetime import datetime, timedelta
from jose import JWTError, jwt

SECRET_KEY = os.getenv("SECRET_KEY")  # Gerado aleatoriamente
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

def criar_access_token(data: dict) -> str:
    """Cria JWT token"""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def verificar_token(token: str) -> dict:
    """Valida e decodifica token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None
```

**Boas práticas JWT:**
- Secret key aleatória e segura (min 32 caracteres)
- Armazenar secret key em variável de ambiente
- Tokens com expiração curta (1 hora)
- Implementar refresh token (7 dias)
- Invalidar token no logout
- Lista negra de tokens revogados (Redis)

#### Controle de Acesso por Perfil
```python
from functools import wraps
from fastapi import HTTPException, status

def requer_perfil(*perfis_permitidos):
    """Decorator para controle de acesso por perfil"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, usuario_atual=None, **kwargs):
            if not usuario_atual:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Não autenticado"
                )
            
            if usuario_atual.perfil not in perfis_permitidos:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Permissão negada"
                )
            
            return await func(*args, usuario_atual=usuario_atual, **kwargs)
        return wrapper
    return decorator

# Uso
@router.post("/equipamentos")
@requer_perfil("TECNICO")
async def criar_equipamento(data: EquipamentoCreate, usuario_atual: Usuario):
    ...
```

### 1.2 Proteção de Dados Sensíveis

#### Variáveis de Ambiente
```python
# .env (NUNCA commitar)
DATABASE_URL=postgresql://user:pass@localhost/monitoring
SECRET_KEY=sua-chave-super-secreta-aqui-32-chars
SMTP_PASSWORD=senha-email
WEBHOOK_TOKEN=token-webhook

# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    secret_key: str
    smtp_password: str
    
    class Config:
        env_file = ".env"

settings = Settings()
```

#### SQL Injection Prevention
```python
# ❌ ERRADO - Vulnerável a SQL injection
query = f"SELECT * FROM usuarios WHERE email = '{email}'"

# ✅ CORRETO - Usar ORM ou parâmetros
usuario = db.query(Usuario).filter(Usuario.email == email).first()
```

#### XSS Prevention
```python
from markupsafe import escape

def sanitizar_input(texto: str) -> str:
    """Remove tags HTML e caracteres perigosos"""
    return escape(texto).strip()
```

### 1.3 Rate Limiting

```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

# Limite global
@app.post("/auth/login")
@limiter.limit("5/minute")
async def login(request: Request, data: LoginRequest):
    ...

# Limite por usuário
@app.post("/heartbeat")
@limiter.limit("2/minute")
async def heartbeat(request: Request, data: HeartbeatCreate):
    ...
```

### 1.4 HTTPS Obrigatório

```python
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware

# Redirecionar HTTP para HTTPS em produção
if os.getenv("ENVIRONMENT") == "production":
    app.add_middleware(HTTPSRedirectMiddleware)
```

---

## 2. ESCALABILIDADE

### 2.1 Otimização de Queries

#### Uso de Índices
```python
# Criar índices para queries frequentes
class Equipamento(Base):
    __tablename__ = "equipamentos"
    
    id = Column(Integer, primary_key=True)
    id_equipamento = Column(String, unique=True, index=True)  # ✅
    setor_id = Column(Integer, ForeignKey("setores.id"), index=True)  # ✅
    status_atual = Column(String, index=True)  # ✅
```

#### Eager Loading
```python
# ❌ ERRADO - N+1 queries
equipamentos = db.query(Equipamento).all()
for eq in equipamentos:
    print(eq.setor.nome)  # Query adicional para cada equipamento

# ✅ CORRETO - Eager loading
from sqlalchemy.orm import joinedload

equipamentos = db.query(Equipamento)\
    .options(joinedload(Equipamento.setor))\
    .all()
```

#### Paginação
```python
def listar_equipamentos(db: Session, skip: int = 0, limit: int = 50):
    """Lista equipamentos com paginação"""
    return db.query(Equipamento)\
        .offset(skip)\
        .limit(limit)\
        .all()
```

### 2.2 Cache

#### Redis para Cache
```python
import redis
import json
from functools import wraps

redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)

def cache_result(ttl: int = 60):
    """Decorator para cachear resultados"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Criar chave de cache
            cache_key = f"{func.__name__}:{str(args)}:{str(kwargs)}"
            
            # Tentar buscar do cache
            cached = redis_client.get(cache_key)
            if cached:
                return json.loads(cached)
            
            # Executar função
            result = await func(*args, **kwargs)
            
            # Salvar no cache
            redis_client.setex(
                cache_key,
                ttl,
                json.dumps(result, default=str)
            )
            
            return result
        return wrapper
    return decorator

# Uso
@cache_result(ttl=300)  # Cache por 5 minutos
async def get_dashboard_resumo(db: Session):
    ...
```

### 2.3 Processamento Assíncrono

```python
from celery import Celery

celery_app = Celery('monitoring', broker='redis://localhost:6379')

@celery_app.task
def processar_planilha_async(arquivo_path: str):
    """Processa importação de planilha em background"""
    # Processamento pesado aqui
    ...

# Uso na API
@router.post("/importar-planilha")
async def importar_planilha(file: UploadFile):
    # Salvar arquivo
    file_path = salvar_arquivo(file)
    
    # Processar em background
    processar_planilha_async.delay(file_path)
    
    return {"mensagem": "Processamento iniciado"}
```

### 2.4 Connection Pooling

```python
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

engine = create_engine(
    DATABASE_URL,
    poolclass=QueuePool,
    pool_size=20,          # Conexões normais
    max_overflow=10,       # Conexões extras
    pool_timeout=30,       # Timeout em segundos
    pool_recycle=3600      # Reciclar conexões a cada hora
)
```

---

## 3. MONITORAMENTO E OBSERVABILIDADE

### 3.1 Logging Estruturado

```python
import logging
import json
from datetime import datetime

class JSONFormatter(logging.Formatter):
    """Formatter para logs em JSON"""
    
    def format(self, record):
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "service": "monitoring-api",
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno
        }
        
        # Adicionar campos extras
        if hasattr(record, 'user_id'):
            log_data['user_id'] = record.user_id
        if hasattr(record, 'ip'):
            log_data['ip'] = record.ip
            
        return json.dumps(log_data)

# Configurar logger
logger = logging.getLogger("monitoring")
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Uso
logger.info("Heartbeat recebido", extra={
    'user_id': usuario.id,
    'equipamento_id': equipamento.id,
    'ip': request.client.host
})
```

### 3.2 Métricas Prometheus

```python
from prometheus_client import Counter, Histogram, Gauge
from prometheus_fastapi_instrumentator import Instrumentator

# Métricas customizadas
heartbeat_counter = Counter(
    'heartbeats_total',
    'Total de heartbeats recebidos',
    ['equipamento', 'status']
)

request_duration = Histogram(
    'request_duration_seconds',
    'Duração das requisições',
    ['method', 'endpoint']
)

equipamentos_online = Gauge(
    'equipamentos_online',
    'Equipamentos atualmente online'
)

# Instrumentar FastAPI
instrumentator = Instrumentator()
instrumentator.instrument(app).expose(app, endpoint="/metrics")
```

### 3.3 Health Checks

```python
@router.get("/health")
async def health_check(db: Session = Depends(get_db)):
    """Verifica saúde do sistema"""
    
    checks = {
        "status": "healthy",
        "timestamp": datetime.utcnow(),
        "checks": {}
    }
    
    # Verificar database
    try:
        db.execute("SELECT 1")
        checks["checks"]["database"] = "ok"
    except:
        checks["status"] = "unhealthy"
        checks["checks"]["database"] = "error"
    
    # Verificar Redis
    try:
        redis_client.ping()
        checks["checks"]["redis"] = "ok"
    except:
        checks["checks"]["redis"] = "error"
    
    # Verificar job scheduler
    if scheduler.running:
        checks["checks"]["scheduler"] = "ok"
    else:
        checks["status"] = "degraded"
        checks["checks"]["scheduler"] = "not running"
    
    status_code = 200 if checks["status"] == "healthy" else 503
    return JSONResponse(content=checks, status_code=status_code)
```

### 3.4 Tracing Distribuído

```python
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

tracer = trace.get_tracer(__name__)

@router.post("/heartbeat")
async def heartbeat(data: HeartbeatCreate):
    with tracer.start_as_current_span("processar_heartbeat"):
        # Sua lógica aqui
        ...
```

---

## 4. TESTES

### 4.1 Testes Unitários

```python
import pytest
from app.core.security import hash_senha, verificar_senha

def test_hash_senha():
    """Testa hash de senha"""
    senha = "teste123"
    hash = hash_senha(senha)
    
    assert hash != senha
    assert len(hash) > 50
    assert verificar_senha(senha, hash)
    assert not verificar_senha("errado", hash)

@pytest.mark.asyncio
async def test_criar_equipamento(client, db_session):
    """Testa criação de equipamento"""
    response = await client.post(
        "/api/v1/equipamentos",
        json={
            "tipo": "COMPUTADOR",
            "setor_id": 1,
            "numero_fisico": "99"
        },
        headers={"Authorization": f"Bearer {token_tecnico}"}
    )
    
    assert response.status_code == 201
    assert response.json()["id_equipamento"] == "PC-EMB-99"
```

### 4.2 Testes de Integração

```python
def test_fluxo_completo_heartbeat(client, db_session):
    """Testa fluxo completo de heartbeat"""
    
    # 1. Criar equipamento
    equipamento = criar_equipamento(db_session)
    
    # 2. Enviar heartbeat
    response = client.post("/api/v1/heartbeat", json={
        "id_equipamento": equipamento.id_equipamento,
        "ip_origem": "192.168.1.100"
    })
    assert response.status_code == 200
    
    # 3. Verificar que foi atualizado
    db_session.refresh(equipamento)
    assert equipamento.ultimo_heartbeat is not None
    assert equipamento.status_atual == "ATIVO"
```

### 4.3 Testes de Carga

```python
# locust_test.py
from locust import HttpUser, task, between

class MonitoringUser(HttpUser):
    wait_time = between(1, 3)
    
    def on_start(self):
        """Login antes dos testes"""
        response = self.client.post("/api/v1/auth/login", json={
            "email": "teste@empresa.com",
            "senha": "teste123"
        })
        self.token = response.json()["access_token"]
    
    @task(3)
    def enviar_heartbeat(self):
        """Simula envio de heartbeat"""
        self.client.post(
            "/api/v1/heartbeat",
            json={
                "id_equipamento": "PC-EMB-01",
                "ip_origem": "192.168.1.100"
            },
            headers={"Authorization": f"Bearer {self.token}"}
        )
    
    @task(1)
    def listar_equipamentos(self):
        """Simula listagem de equipamentos"""
        self.client.get(
            "/api/v1/equipamentos",
            headers={"Authorization": f"Bearer {self.token}"}
        )

# Executar: locust -f locust_test.py --host=http://localhost:8000
```

---

## 5. DEPLOY E INFRAESTRUTURA

### 5.1 Docker

```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Instalar dependências do sistema
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Instalar dependências Python
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar código
COPY . .

# Variáveis de ambiente padrão
ENV PYTHONUNBUFFERED=1
ENV ENVIRONMENT=production

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8000/health || exit 1

# Comando de inicialização
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/monitoring
      - REDIS_URL=redis://redis:6379
    depends_on:
      - db
      - redis
    restart: unless-stopped
  
  db:
    image: postgres:14
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=monitoring
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
  
  redis:
    image: redis:7-alpine
    restart: unless-stopped
  
  scheduler:
    build: .
    command: python -m app.services.scheduler
    depends_on:
      - db
      - redis
    restart: unless-stopped

volumes:
  postgres_data:
```

### 5.2 CI/CD (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-cov
      
      - name: Run tests
        run: pytest --cov=app tests/
        env:
          DATABASE_URL: postgresql://test:test@localhost/test_db
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

### 5.3 Backup Automático

```bash
#!/bin/bash
# backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups"
DB_NAME="monitoring"
DB_USER="postgres"

# Backup do banco
pg_dump -U $DB_USER $DB_NAME | gzip > "$BACKUP_DIR/db_$DATE.sql.gz"

# Manter apenas últimos 30 dias
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +30 -delete

# Upload para S3 (opcional)
# aws s3 cp "$BACKUP_DIR/db_$DATE.sql.gz" s3://bucket/backups/
```

---

## 6. DOCUMENTAÇÃO

### 6.1 OpenAPI/Swagger

```python
from fastapi import FastAPI

app = FastAPI(
    title="Sistema de Monitoramento",
    description="API para monitoramento de equipamentos",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Acessível em: http://localhost:8000/docs
```

### 6.2 README.md Completo

```markdown
# Sistema de Monitoramento de Equipamentos

## Instalação

```bash
# Clonar repositório
git clone https://github.com/empresa/monitoring

# Criar ambiente virtual
python -m venv venv
source venv/bin/activate  # Linux/Mac
venv\Scripts\activate     # Windows

# Instalar dependências
pip install -r requirements.txt

# Configurar banco de dados
createdb monitoring
psql monitoring < scripts/schema.sql

# Executar
uvicorn app.main:app --reload
```

## Configuração

Copiar `.env.example` para `.env` e configurar variáveis.

## Testes

```bash
pytest
```

## Deploy

Ver documentação em `docs/DEPLOY.md`
```

---

## RESUMO DAS MELHORES PRÁTICAS

✅ **Segurança**
- JWT com expiração curta
- Bcrypt para senhas
- HTTPS obrigatório
- Rate limiting
- Validação de inputs

✅ **Performance**
- Cache Redis
- Connection pooling
- Índices otimizados
- Paginação
- Processamento assíncrono

✅ **Confiabilidade**
- Logs estruturados
- Métricas Prometheus
- Health checks
- Testes automatizados
- Backups automáticos

✅ **Manutenibilidade**
- Código limpo e documentado
- Testes > 80% cobertura
- CI/CD automatizado
- Versionamento semântico
- Documentação atualizada
