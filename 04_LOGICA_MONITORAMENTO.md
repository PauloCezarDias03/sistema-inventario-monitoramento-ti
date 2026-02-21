# LÓGICA DE MONITORAMENTO - Sistema de Heartbeat

## Visão Geral

Sistema de monitoramento contínuo baseado em heartbeat (sinal de vida) enviado periodicamente pelos equipamentos para a API central.

---

## ARQUITETURA DO MONITORAMENTO

```
┌─────────────────┐                  ┌──────────────────┐
│   Equipamento   │    Heartbeat     │   API Central    │
│  (PC ou Totem)  │ ───────────────> │   (FastAPI)      │
│                 │    A cada 1min   │                  │
└─────────────────┘                  └────────┬─────────┘
                                              │
                                              │ Registra
                                              ▼
                                     ┌──────────────────┐
                                     │   PostgreSQL     │
                                     │  (heartbeats)    │
                                     └──────────────────┘
                                              │
                                              │ Monitora
                                              ▼
                                     ┌──────────────────┐
                                     │  Timeout Checker │
                                     │  (Job Agendado)  │
                                     └────────┬─────────┘
                                              │
                                              │ Detecta inatividade
                                              ▼
                                     ┌──────────────────┐
                                     │ Sistema Alertas  │
                                     │  (Notificações)  │
                                     └──────────────────┘
```

---

## INTERVALOS E TIMEOUTS

### Configurações Padrão

| Parâmetro | Valor | Descrição |
|-----------|-------|-----------|
| HEARTBEAT_INTERVAL | 60 segundos | Intervalo entre envios |
| HEARTBEAT_TIMEOUT | 300 segundos (5 min) | Tempo máximo sem sinal |
| TOLERANCE_FACTOR | 1.5x | Fator de tolerância |
| CHECK_INTERVAL | 60 segundos | Frequência da verificação |
| RETRY_ATTEMPTS | 3 | Tentativas antes de falhar |
| RETRY_DELAY | 10 segundos | Delay entre tentativas |

### Cálculo de Timeout
```
timeout_real = HEARTBEAT_INTERVAL * TOLERANCE_FACTOR
timeout_real = 60 * 1.5 = 90 segundos

Após 90 segundos sem heartbeat:
  - Status: ainda ATIVO (dentro da margem)

Após 300 segundos (5 minutos) sem heartbeat:
  - Status: muda para INATIVO
  - Alerta gerado
```

---

## FLUXO DE HEARTBEAT

### 1. Envio do Heartbeat (Cliente)

```python
import requests
import time
import socket
from datetime import datetime

class HeartbeatClient:
    """Cliente de heartbeat para equipamentos"""
    
    def __init__(self, api_url, id_equipamento):
        self.api_url = api_url
        self.id_equipamento = id_equipamento
        self.interval = 60  # segundos
        
    def get_system_info(self):
        """Coleta informações do sistema"""
        return {
            "cpu_usage": self._get_cpu_usage(),
            "memory_usage": self._get_memory_usage(),
            "disk_usage": self._get_disk_usage(),
            "uptime_seconds": self._get_uptime()
        }
    
    def send_heartbeat(self):
        """Envia heartbeat para a API"""
        try:
            payload = {
                "id_equipamento": self.id_equipamento,
                "ip_origem": self._get_local_ip(),
                "metadados": self.get_system_info()
            }
            
            response = requests.post(
                f"{self.api_url}/api/v1/heartbeat",
                json=payload,
                timeout=5
            )
            
            if response.status_code == 200:
                print(f"[{datetime.now()}] Heartbeat enviado com sucesso")
                return True
            else:
                print(f"[{datetime.now()}] Erro: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"[{datetime.now()}] Falha ao enviar heartbeat: {e}")
            return False
    
    def run(self):
        """Loop principal de heartbeat"""
        print(f"Iniciando heartbeat para {self.id_equipamento}")
        print(f"Intervalo: {self.interval}s")
        
        while True:
            self.send_heartbeat()
            time.sleep(self.interval)
    
    def _get_local_ip(self):
        """Obtém IP local da máquina"""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "unknown"
    
    def _get_cpu_usage(self):
        """Retorna uso de CPU (implementação depende do SO)"""
        import psutil
        return psutil.cpu_percent(interval=1)
    
    def _get_memory_usage(self):
        """Retorna uso de memória"""
        import psutil
        return psutil.virtual_memory().percent
    
    def _get_disk_usage(self):
        """Retorna uso de disco"""
        import psutil
        return psutil.disk_usage('/').percent
    
    def _get_uptime(self):
        """Retorna uptime em segundos"""
        import psutil
        return int(time.time() - psutil.boot_time())


# Uso
if __name__ == "__main__":
    client = HeartbeatClient(
        api_url="http://api.empresa.com",
        id_equipamento="PC-EMB-01"
    )
    client.run()
```

---

### 2. Recebimento do Heartbeat (API)

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime
from app.schemas.heartbeat import HeartbeatCreate
from app.db.session import get_db
from app.db.models import Equipamento, Heartbeat

router = APIRouter()

@router.post("/heartbeat")
async def registrar_heartbeat(
    data: HeartbeatCreate,
    db: Session = Depends(get_db)
):
    """
    Registra heartbeat de um equipamento.
    
    - Valida se equipamento existe
    - Registra heartbeat no banco
    - Atualiza último_heartbeat do equipamento
    - Atualiza status se estava INATIVO
    """
    
    # Buscar equipamento
    equipamento = db.query(Equipamento).filter(
        Equipamento.id_equipamento == data.id_equipamento
    ).first()
    
    if not equipamento:
        raise HTTPException(
            status_code=404,
            detail=f"Equipamento {data.id_equipamento} não encontrado"
        )
    
    # Criar registro de heartbeat
    heartbeat = Heartbeat(
        equipamento_id=equipamento.id,
        timestamp=datetime.utcnow(),
        ip_origem=data.ip_origem,
        metadados=data.metadados
    )
    db.add(heartbeat)
    
    # Atualizar equipamento
    status_anterior = equipamento.status_atual
    equipamento.ultimo_heartbeat = datetime.utcnow()
    
    # Se estava inativo, reativar
    if equipamento.status_atual == 'INATIVO':
        equipamento.status_atual = 'ATIVO'
    
    db.commit()
    db.refresh(equipamento)
    
    return {
        "success": True,
        "equipamento_id": equipamento.id,
        "timestamp": heartbeat.timestamp,
        "status_atualizado": equipamento.status_atual,
        "mensagem": "Heartbeat registrado com sucesso"
    }
```

---

### 3. Verificação de Timeout (Job Agendado)

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from app.db.session import SessionLocal
from app.db.models import Equipamento
from app.core.alerts import enviar_alerta_inatividade

scheduler = AsyncIOScheduler()

async def verificar_timeouts():
    """
    Job agendado que verifica equipamentos inativos.
    
    Executa a cada 60 segundos.
    - Busca equipamentos sem heartbeat recente
    - Atualiza status para INATIVO
    - Dispara alertas
    """
    
    db = SessionLocal()
    
    try:
        # Tempo limite: 5 minutos atrás
        timeout_limite = datetime.utcnow() - timedelta(seconds=300)
        
        # Buscar equipamentos ativos com timeout
        equipamentos_timeout = db.query(Equipamento).filter(
            Equipamento.status_atual == 'ATIVO',
            Equipamento.ultimo_heartbeat < timeout_limite
        ).all()
        
        for equipamento in equipamentos_timeout:
            # Calcular tempo inativo
            segundos_inativo = int(
                (datetime.utcnow() - equipamento.ultimo_heartbeat).total_seconds()
            )
            
            print(f"Equipamento {equipamento.id_equipamento} inativo há {segundos_inativo}s")
            
            # Atualizar status
            equipamento.status_atual = 'INATIVO'
            
            # Enviar alerta
            await enviar_alerta_inatividade(equipamento, segundos_inativo)
        
        # Salvar alterações
        if equipamentos_timeout:
            db.commit()
            print(f"{len(equipamentos_timeout)} equipamento(s) marcado(s) como INATIVO")
        
    except Exception as e:
        print(f"Erro ao verificar timeouts: {e}")
        db.rollback()
    
    finally:
        db.close()


# Configurar job
def iniciar_monitoramento():
    """Inicia o scheduler de monitoramento"""
    
    # Verificar timeouts a cada 60 segundos
    scheduler.add_job(
        verificar_timeouts,
        'interval',
        seconds=60,
        id='verificar_timeouts',
        replace_existing=True
    )
    
    scheduler.start()
    print("Monitoramento de timeouts iniciado")
```

---

## SISTEMA DE ALERTAS

### Tipos de Alerta

1. **Equipamento Inativo**
   - Trigger: Status muda para INATIVO
   - Prioridade: ALTA
   - Destinatários: Técnicos de TI

2. **Equipamento Crítico Inativo**
   - Trigger: Equipamento crítico fica inativo
   - Prioridade: URGENTE
   - Destinatários: Todos os técnicos + Supervisor

3. **Múltiplos Equipamentos Inativos**
   - Trigger: > 3 equipamentos inativos no mesmo setor
   - Prioridade: ALTA
   - Destinatários: Técnico responsável pelo setor

### Implementação de Alertas

```python
from typing import List
from app.db.models import Equipamento, Usuario
from app.services.notification import enviar_email, enviar_webhook

async def enviar_alerta_inatividade(equipamento: Equipamento, segundos_inativo: int):
    """
    Envia alertas quando equipamento fica inativo.
    
    - Email para técnicos
    - Webhook para sistema externo
    - Log no histórico
    """
    
    # Buscar técnicos ativos
    tecnicos = db.query(Usuario).filter(
        Usuario.perfil == 'TECNICO',
        Usuario.ativo == True
    ).all()
    
    # Preparar mensagem
    tempo_formatado = formatar_tempo_inativo(segundos_inativo)
    
    mensagem = {
        "tipo": "EQUIPAMENTO_INATIVO",
        "prioridade": "URGENTE" if equipamento.critico else "ALTA",
        "equipamento": {
            "id": equipamento.id_equipamento,
            "tipo": equipamento.tipo,
            "setor": equipamento.setor.nome,
            "funcao": equipamento.funcao
        },
        "tempo_inativo": tempo_formatado,
        "timestamp": datetime.utcnow().isoformat()
    }
    
    # Enviar email
    for tecnico in tecnicos:
        await enviar_email(
            destinatario=tecnico.email,
            assunto=f"ALERTA: {equipamento.id_equipamento} INATIVO",
            corpo=gerar_email_alerta(mensagem)
        )
    
    # Enviar webhook (se configurado)
    webhook_url = os.getenv("WEBHOOK_ALERTAS")
    if webhook_url:
        await enviar_webhook(webhook_url, mensagem)
    
    # Registrar no histórico
    registrar_alerta_historico(equipamento.id, mensagem)


def formatar_tempo_inativo(segundos: int) -> str:
    """Formata segundos em string legível"""
    
    if segundos < 60:
        return f"{segundos}s"
    elif segundos < 3600:
        minutos = segundos // 60
        return f"{minutos}m"
    elif segundos < 86400:
        horas = segundos // 3600
        minutos = (segundos % 3600) // 60
        return f"{horas}h {minutos}m"
    else:
        dias = segundos // 86400
        horas = (segundos % 86400) // 3600
        return f"{dias}d {horas}h"
```

---

## TRATAMENTO DE FALHAS

### Cenários de Falha

#### 1. Equipamento sem conectividade
```
Sintoma: Não envia heartbeat
Detecção: Timeout após 5 minutos
Ação: 
  - Marcar como INATIVO
  - Enviar alerta
  - Registrar no histórico
```

#### 2. API temporariamente indisponível
```
Sintoma: Cliente não consegue enviar heartbeat
Comportamento do Cliente:
  - Retry 3 vezes com delay de 10s
  - Se todas falharem, aguardar próximo intervalo
  - Não marcar equipamento como inativo (API não recebeu confirmação)
```

#### 3. Rede instável (perda de pacotes)
```
Sintoma: Heartbeats intermitentes
Solução:
  - Fator de tolerância de 1.5x
  - Permite perda de 1 heartbeat sem marcar inativo
  - Timeout de 5 minutos (5 heartbeats perdidos)
```

#### 4. Manutenção programada
```
Ação prévia:
  - Técnico marca equipamento como EM_MANUTENCAO
  - Sistema não envia alertas para equipamentos em manutenção
  - Heartbeat continua sendo aceito (se enviado)
```

---

## OTIMIZAÇÕES E PERFORMANCE

### 1. Particionamento de Heartbeats
```sql
-- Tabela particionada por mês
CREATE TABLE heartbeats_2026_01 PARTITION OF heartbeats
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- Purge automático de dados antigos (> 90 dias)
DELETE FROM heartbeats 
WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

### 2. Índices Otimizados
```sql
-- Índice composto para queries de verificação
CREATE INDEX idx_heartbeats_equip_timestamp 
ON heartbeats(equipamento_id, timestamp DESC);

-- Índice parcial para equipamentos ativos
CREATE INDEX idx_equipamentos_ativos_heartbeat 
ON equipamentos(ultimo_heartbeat) 
WHERE status_atual = 'ATIVO';
```

### 3. Cache de Status
```python
# Redis cache para status de equipamentos
import redis

redis_client = redis.Redis(host='localhost', port=6379)

def get_status_cache(id_equipamento: str) -> str:
    """Busca status do cache"""
    cached = redis_client.get(f"status:{id_equipamento}")
    if cached:
        return cached.decode()
    return None

def set_status_cache(id_equipamento: str, status: str):
    """Atualiza cache com TTL de 60s"""
    redis_client.setex(
        f"status:{id_equipamento}", 
        60, 
        status
    )
```

---

## MÉTRICAS E MONITORAMENTO

### Métricas Importantes

```python
from prometheus_client import Counter, Gauge, Histogram

# Contadores
heartbeats_recebidos = Counter(
    'heartbeats_total',
    'Total de heartbeats recebidos',
    ['equipamento', 'status']
)

# Gauges
equipamentos_ativos = Gauge(
    'equipamentos_ativos',
    'Número de equipamentos ativos'
)

equipamentos_inativos = Gauge(
    'equipamentos_inativos',
    'Número de equipamentos inativos'
)

# Histogramas
latencia_heartbeat = Histogram(
    'heartbeat_latency_seconds',
    'Latência do processamento de heartbeat'
)
```

### Dashboard de Monitoramento

```
Equipamentos Online:  ████████████░░ 85%  (12/14)
Equipamentos Offline: ██░░░░░░░░░░░░ 15%  (2/14)

Heartbeats/minuto:    45 ↑
Alertas hoje:         3
Manutenções ativas:   2
Equipamentos críticos: 1

Setores com problemas:
  - Solda: 1 equipamento offline (TOT-SOL-01)
  - Usinagem: 1 equipamento offline (TOT-USI-02)
```

---

## CONFIGURAÇÕES RECOMENDADAS

### Desenvolvimento
```env
HEARTBEAT_INTERVAL=30  # 30 segundos
HEARTBEAT_TIMEOUT=90   # 1.5 minutos
CHECK_INTERVAL=30      # 30 segundos
ENABLE_ALERTS=false    # Desabilitar alertas
```

### Produção
```env
HEARTBEAT_INTERVAL=60   # 1 minuto
HEARTBEAT_TIMEOUT=300   # 5 minutos
CHECK_INTERVAL=60       # 1 minuto
ENABLE_ALERTS=true      # Habilitar alertas
RETRY_ATTEMPTS=3
RETRY_DELAY=10
```

### Alta Disponibilidade
```env
HEARTBEAT_INTERVAL=30   # 30 segundos (mais frequente)
HEARTBEAT_TIMEOUT=150   # 2.5 minutos
CHECK_INTERVAL=30       # 30 segundos
REDIS_CACHE=true        # Usar cache Redis
ENABLE_METRICS=true     # Prometheus metrics
```

---

## CHECKLIST DE IMPLEMENTAÇÃO

- [ ] Cliente de heartbeat instalado em todos os equipamentos
- [ ] Configuração de intervalo adequada ao ambiente
- [ ] Job de verificação de timeout rodando
- [ ] Sistema de alertas configurado
- [ ] Logs estruturados ativados
- [ ] Métricas expostas para monitoramento
- [ ] Particionamento de heartbeats configurado
- [ ] Purge automático de dados antigos
- [ ] Dashboard de monitoramento ativo
- [ ] Documentação de troubleshooting disponível
