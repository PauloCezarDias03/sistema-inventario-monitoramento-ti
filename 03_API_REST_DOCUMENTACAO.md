# API REST - Sistema de Monitoramento de Equipamentos

## Visão Geral

API RESTful desenvolvida em Python/FastAPI para monitoramento em tempo real de computadores e totens.

**Stack Tecnológica:**
- Python 3.11+
- FastAPI (framework web assíncrono)
- SQLAlchemy (ORM)
- PostgreSQL 14+
- Pydantic (validação)
- JWT (autenticação)
- APScheduler (jobs agendados)

---

## ESTRUTURA DO PROJETO

```
monitoring-system/
│
├── app/
│   ├── __init__.py
│   ├── main.py                      # Entry point da aplicação
│   ├── config.py                    # Configurações e variáveis de ambiente
│   │
│   ├── api/                         # Endpoints da API
│   │   ├── __init__.py
│   │   ├── deps.py                  # Dependências (auth, db session)
│   │   ├── v1/
│   │   │   ├── __init__.py
│   │   │   ├── router.py            # Router principal v1
│   │   │   ├── auth.py              # Autenticação e login
│   │   │   ├── equipamentos.py     # CRUD equipamentos
│   │   │   ├── heartbeat.py        # Endpoint de heartbeat
│   │   │   ├── manutencoes.py      # Gestão de manutenções
│   │   │   ├── dashboard.py        # Dados para dashboard
│   │   │   └── historico.py        # Consulta de histórico
│   │
│   ├── core/                        # Lógica de negócio core
│   │   ├── __init__.py
│   │   ├── security.py              # JWT, hash de senha
│   │   ├── monitoring.py            # Lógica de monitoramento
│   │   └── alerts.py                # Sistema de alertas
│   │
│   ├── db/                          # Database
│   │   ├── __init__.py
│   │   ├── base.py                  # Base classes
│   │   ├── session.py               # Database session
│   │   └── models.py                # SQLAlchemy models
│   │
│   ├── schemas/                     # Pydantic schemas
│   │   ├── __init__.py
│   │   ├── usuario.py
│   │   ├── equipamento.py
│   │   ├── heartbeat.py
│   │   ├── manutencao.py
│   │   └── comum.py                 # Schemas reutilizáveis
│   │
│   ├── crud/                        # Database operations
│   │   ├── __init__.py
│   │   ├── base.py                  # CRUD base genérico
│   │   ├── usuario.py
│   │   ├── equipamento.py
│   │   ├── heartbeat.py
│   │   └── manutencao.py
│   │
│   ├── services/                    # Serviços de negócio
│   │   ├── __init__.py
│   │   ├── planilha_sync.py         # Sincronização com planilha
│   │   ├── timeout_checker.py       # Verifica timeouts
│   │   └── notification.py          # Envio de notificações
│   │
│   └── utils/                       # Utilitários
│       ├── __init__.py
│       ├── logger.py                # Configuração de logs
│       └── validators.py            # Validadores customizados
│
├── alembic/                         # Migrations
│   ├── versions/
│   └── env.py
│
├── tests/                           # Testes
│   ├── __init__.py
│   ├── conftest.py
│   ├── test_auth.py
│   ├── test_equipamentos.py
│   └── test_heartbeat.py
│
├── scripts/                         # Scripts utilitários
│   ├── import_planilha.py
│   └── create_admin.py
│
├── .env.example                     # Exemplo de variáveis de ambiente
├── .gitignore
├── requirements.txt                 # Dependências Python
├── pyproject.toml                   # Configuração do projeto
├── docker-compose.yml               # Setup Docker
├── Dockerfile
└── README.md
```

---

## ENDPOINTS DA API

### Base URL: `/api/v1`

### 1. **AUTENTICAÇÃO**

#### POST `/auth/login`
Autenticação de usuário.

**Request:**
```json
{
  "email": "tecnico@empresa.com",
  "senha": "senha123"
}
```

**Response 200:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "expires_in": 3600,
  "usuario": {
    "id": 1,
    "nome": "João Silva",
    "email": "tecnico@empresa.com",
    "perfil": "TECNICO"
  }
}
```

**Validações:**
- Email válido
- Senha mínima de 6 caracteres
- Usuário ativo

---

#### POST `/auth/refresh`
Renovar token de acesso.

**Headers:**
```
Authorization: Bearer {token}
```

**Response 200:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "expires_in": 3600
}
```

---

#### GET `/auth/me`
Dados do usuário autenticado.

**Headers:**
```
Authorization: Bearer {token}
```

**Response 200:**
```json
{
  "id": 1,
  "nome": "João Silva",
  "email": "tecnico@empresa.com",
  "perfil": "TECNICO",
  "ativo": true,
  "created_at": "2026-01-15T10:30:00"
}
```

---

### 2. **EQUIPAMENTOS**

#### GET `/equipamentos`
Listar todos os equipamentos (técnico) ou apenas do usuário (comum).

**Query Parameters:**
- `setor_id` (optional): Filtrar por setor
- `tipo` (optional): COMPUTADOR | TOTEM
- `status` (optional): ATIVO | INATIVO | EM_MANUTENCAO
- `critico` (optional): true | false
- `page` (default: 1)
- `limit` (default: 50)

**Response 200:**
```json
{
  "total": 14,
  "page": 1,
  "limit": 50,
  "items": [
    {
      "id": 1,
      "id_equipamento": "PC-EMB-01",
      "tipo": "COMPUTADOR",
      "setor": {
        "id": 1,
        "nome": "Embalagem",
        "abreviacao": "EMB"
      },
      "numero_fisico": "01",
      "funcao": "Apontamento_MK",
      "codigo_visual_atual": "Comp.:(Apontamento_MK)#1",
      "status_atual": "ATIVO",
      "ultimo_heartbeat": "2026-01-30T14:25:00",
      "segundos_inativo": 120,
      "critico": false,
      "observacoes": null
    }
  ]
}
```

---

#### GET `/equipamentos/{id}`
Detalhes de um equipamento específico.

**Response 200:**
```json
{
  "id": 1,
  "id_equipamento": "PC-EMB-01",
  "tipo": "COMPUTADOR",
  "setor": {
    "id": 1,
    "nome": "Embalagem",
    "abreviacao": "EMB"
  },
  "numero_fisico": "01",
  "funcao": "Apontamento_MK",
  "codigo_visual_atual": "Comp.:(Apontamento_MK)#1",
  "status_atual": "ATIVO",
  "ultimo_heartbeat": "2026-01-30T14:25:00",
  "segundos_inativo": 120,
  "critico": false,
  "observacoes": null,
  "created_at": "2026-01-28T10:00:00",
  "updated_at": "2026-01-30T14:25:00",
  "manutencoes_recentes": [
    {
      "id": 5,
      "tipo_manutencao": "CORRETIVA",
      "descricao": "Substituição de memória RAM",
      "data_inicio": "2026-01-25T09:00:00",
      "data_fim": "2026-01-25T11:30:00",
      "resolvido": true
    }
  ]
}
```

---

#### POST `/equipamentos`
Criar novo equipamento (apenas TECNICO).

**Request:**
```json
{
  "tipo": "COMPUTADOR",
  "setor_id": 1,
  "numero_fisico": "05",
  "funcao": "Conferência",
  "codigo_visual_atual": "Comp.:(Conferência)#5",
  "observacoes": "Equipamento novo"
}
```

**Response 201:**
```json
{
  "id": 15,
  "id_equipamento": "PC-EMB-05",
  "tipo": "COMPUTADOR",
  "setor": {
    "id": 1,
    "nome": "Embalagem",
    "abreviacao": "EMB"
  },
  "numero_fisico": "05",
  "funcao": "Conferência",
  "status_atual": "ATIVO",
  "critico": false
}
```

**Validações:**
- tipo: COMPUTADOR ou TOTEM
- setor_id: deve existir e estar ativo
- numero_fisico: obrigatório
- id_equipamento gerado automaticamente

---

#### PATCH `/equipamentos/{id}`
Atualizar equipamento (apenas TECNICO).

**Request:**
```json
{
  "status_atual": "EM_MANUTENCAO",
  "observacoes": "Manutenção preventiva agendada"
}
```

**Response 200:**
```json
{
  "id": 1,
  "id_equipamento": "PC-EMB-01",
  "status_atual": "EM_MANUTENCAO",
  "observacoes": "Manutenção preventiva agendada",
  "updated_at": "2026-01-30T15:00:00"
}
```

---

#### DELETE `/equipamentos/{id}`
Remover equipamento (apenas TECNICO - soft delete).

**Response 204:** No content

---

### 3. **HEARTBEAT**

#### POST `/heartbeat`
Registrar sinal de vida do equipamento.

**Request:**
```json
{
  "id_equipamento": "PC-EMB-01",
  "ip_origem": "192.168.1.100",
  "metadados": {
    "cpu_usage": 45.2,
    "memory_usage": 62.8,
    "disk_usage": 78.5,
    "uptime_seconds": 86400
  }
}
```

**Response 200:**
```json
{
  "success": true,
  "equipamento_id": 1,
  "timestamp": "2026-01-30T14:27:00",
  "status_atualizado": "ATIVO",
  "mensagem": "Heartbeat registrado com sucesso"
}
```

**Validações:**
- id_equipamento: deve existir
- Aceita metadados opcionais em JSON
- Atualiza automaticamente último_heartbeat
- Muda status de INATIVO para ATIVO se necessário

---

#### GET `/heartbeat/{id_equipamento}/historico`
Histórico de heartbeats de um equipamento.

**Query Parameters:**
- `data_inicio` (optional): ISO 8601
- `data_fim` (optional): ISO 8601
- `limit` (default: 100)

**Response 200:**
```json
{
  "equipamento": "PC-EMB-01",
  "total": 245,
  "heartbeats": [
    {
      "timestamp": "2026-01-30T14:27:00",
      "ip_origem": "192.168.1.100",
      "metadados": {
        "cpu_usage": 45.2,
        "memory_usage": 62.8
      }
    }
  ]
}
```

---

### 4. **MANUTENÇÕES**

#### GET `/manutencoes`
Listar manutenções.

**Query Parameters:**
- `equipamento_id` (optional)
- `tecnico_id` (optional)
- `tipo_manutencao` (optional): PREVENTIVA | CORRETIVA | EMERGENCIAL
- `resolvido` (optional): true | false
- `data_inicio` (optional): Data inicial
- `data_fim` (optional): Data final
- `page` (default: 1)
- `limit` (default: 50)

**Response 200:**
```json
{
  "total": 23,
  "page": 1,
  "items": [
    {
      "id": 5,
      "equipamento": {
        "id": 1,
        "id_equipamento": "PC-EMB-01",
        "tipo": "COMPUTADOR"
      },
      "tecnico": {
        "id": 1,
        "nome": "João Silva"
      },
      "tipo_manutencao": "CORRETIVA",
      "descricao": "Substituição de memória RAM",
      "data_inicio": "2026-01-25T09:00:00",
      "data_fim": "2026-01-25T11:30:00",
      "resolvido": true,
      "observacoes": "Memória antiga apresentava erros",
      "created_at": "2026-01-25T09:00:00"
    }
  ]
}
```

---

#### POST `/manutencoes`
Registrar nova manutenção (apenas TECNICO).

**Request:**
```json
{
  "equipamento_id": 1,
  "tipo_manutencao": "PREVENTIVA",
  "descricao": "Limpeza geral e atualização de drivers",
  "data_inicio": "2026-01-30T16:00:00",
  "observacoes": "Manutenção trimestral"
}
```

**Response 201:**
```json
{
  "id": 24,
  "equipamento_id": 1,
  "tecnico_id": 1,
  "tipo_manutencao": "PREVENTIVA",
  "descricao": "Limpeza geral e atualização de drivers",
  "data_inicio": "2026-01-30T16:00:00",
  "data_fim": null,
  "resolvido": false,
  "created_at": "2026-01-30T15:30:00"
}
```

**Validações:**
- equipamento_id: deve existir
- tipo_manutencao: PREVENTIVA | CORRETIVA | EMERGENCIAL
- descricao: obrigatória (mínimo 10 caracteres)
- Atualiza status do equipamento para EM_MANUTENCAO

---

#### PATCH `/manutencoes/{id}/finalizar`
Finalizar manutenção (apenas TECNICO).

**Request:**
```json
{
  "data_fim": "2026-01-30T17:30:00",
  "resolvido": true,
  "observacoes": "Problema resolvido, equipamento testado"
}
```

**Response 200:**
```json
{
  "id": 24,
  "data_fim": "2026-01-30T17:30:00",
  "resolvido": true,
  "observacoes": "Problema resolvido, equipamento testado"
}
```

**Ações automáticas:**
- Atualiza status do equipamento para ATIVO
- Recalcula criticidade do equipamento

---

### 5. **DASHBOARD**

#### GET `/dashboard/resumo`
Resumo geral do sistema.

**Response 200:**
```json
{
  "total_equipamentos": 14,
  "total_ativos": 10,
  "total_inativos": 2,
  "total_em_manutencao": 2,
  "total_criticos": 3,
  "por_tipo": {
    "COMPUTADOR": 5,
    "TOTEM": 9
  },
  "por_setor": [
    {
      "setor": "Embalagem",
      "total": 6,
      "ativos": 5,
      "inativos": 1,
      "criticos": 2
    }
  ],
  "alertas_ativos": 2
}
```

---

#### GET `/dashboard/setores`
Detalhamento por setor.

**Response 200:**
```json
[
  {
    "setor_id": 1,
    "setor": "Embalagem",
    "abreviacao": "EMB",
    "total_equipamentos": 6,
    "computadores": 3,
    "totens": 3,
    "ativos": 5,
    "inativos": 1,
    "em_manutencao": 0,
    "criticos": 2
  }
]
```

---

#### GET `/dashboard/equipamentos-inativos`
Lista de equipamentos inativos com tempo de inatividade.

**Response 200:**
```json
[
  {
    "id": 3,
    "id_equipamento": "PC-EMB-03",
    "tipo": "COMPUTADOR",
    "setor": "Embalagem",
    "ultimo_heartbeat": "2026-01-30T12:00:00",
    "segundos_inativo": 9000,
    "tempo_inativo_formatado": "2h 30m",
    "critico": false
  }
]
```

---

### 6. **HISTÓRICO**

#### GET `/historico/equipamento/{id}`
Histórico de alterações de um equipamento.

**Query Parameters:**
- `limit` (default: 50)

**Response 200:**
```json
{
  "equipamento": "PC-EMB-01",
  "total": 15,
  "alteracoes": [
    {
      "id": 45,
      "timestamp": "2026-01-30T14:00:00",
      "usuario": "João Silva",
      "campo_alterado": "status_atual",
      "valor_anterior": "EM_MANUTENCAO",
      "valor_novo": "ATIVO",
      "tipo_alteracao": "UPDATE",
      "motivo": "Manutenção concluída"
    }
  ]
}
```

---

## CÓDIGOS DE RESPOSTA HTTP

| Código | Significado | Uso |
|--------|-------------|-----|
| 200 | OK | Requisição bem-sucedida |
| 201 | Created | Recurso criado com sucesso |
| 204 | No Content | Recurso deletado com sucesso |
| 400 | Bad Request | Dados inválidos na requisição |
| 401 | Unauthorized | Token ausente ou inválido |
| 403 | Forbidden | Usuário sem permissão |
| 404 | Not Found | Recurso não encontrado |
| 422 | Unprocessable Entity | Validação falhou |
| 500 | Internal Server Error | Erro no servidor |

---

## AUTENTICAÇÃO E SEGURANÇA

### JWT Token
- Algoritmo: HS256
- Expiração: 1 hora
- Refresh: 7 dias
- Claims: user_id, email, perfil

### Headers Obrigatórios
```
Authorization: Bearer {token}
Content-Type: application/json
```

### Permissões por Perfil

**TECNICO:**
- Acesso total a todos os endpoints
- CRUD completo em equipamentos
- Registro de manutenções
- Visualização de todo o sistema

**USUARIO:**
- GET /equipamentos (apenas sua máquina)
- GET /equipamentos/{id} (apenas sua máquina)
- POST /heartbeat (apenas sua máquina)
- Sem acesso a manutenções e histórico completo

---

## RATE LIMITING

- Autenticação: 5 tentativas / minuto / IP
- Heartbeat: 1 chamada / 30 segundos / equipamento
- Demais endpoints: 100 chamadas / minuto / usuário

---

## PAGINAÇÃO

Padrão para listagens:
```
GET /equipamentos?page=2&limit=20
```

Response inclui:
```json
{
  "total": 100,
  "page": 2,
  "limit": 20,
  "total_pages": 5,
  "items": [...]
}
```

---

## VALIDAÇÕES GLOBAIS

### Equipamento
- id_equipamento: formato `^(PC|TOT)-[A-Z]{3}-\d{2}$`
- tipo: COMPUTADOR | TOTEM
- status_atual: ATIVO | INATIVO | EM_MANUTENCAO
- numero_fisico: obrigatório

### Manutenção
- descricao: mínimo 10 caracteres
- tipo_manutencao: PREVENTIVA | CORRETIVA | EMERGENCIAL
- data_fim >= data_inicio

### Usuário
- email: formato válido
- senha: mínimo 6 caracteres
- perfil: TECNICO | USUARIO

---

## LOGS E MONITORAMENTO

### Estrutura de Logs
```json
{
  "timestamp": "2026-01-30T14:30:00",
  "level": "INFO",
  "service": "monitoring-api",
  "endpoint": "/api/v1/heartbeat",
  "method": "POST",
  "user_id": 1,
  "ip": "192.168.1.100",
  "duration_ms": 45,
  "status_code": 200
}
```

### Métricas Expostas
- `/metrics` (Prometheus format)
- Total de requisições
- Latência por endpoint
- Equipamentos online/offline
- Taxa de heartbeats recebidos

---

## WEBSOCKETS (Opcional - Fase 2)

```
ws://api.domain.com/ws/equipamentos

{
  "type": "status_change",
  "equipamento_id": "PC-EMB-01",
  "status_anterior": "ATIVO",
  "status_novo": "INATIVO",
  "timestamp": "2026-01-30T14:30:00"
}
```
