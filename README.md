# PoC — Comparativo técnico de Garbage Collectors no Java 25
## G1GC vs ZGC vs ShenandoahGC

Este repositório contém uma prova de conceito para comparar, de forma reproduzível, o desempenho dos coletores de lixo do Java 25: **G1GC**, **ZGC** e **ShenandoahGC**. O projeto padroniza ambiente, aplica warm‑up, executa carga controlada e coleta métricas de latência e de GC, consolidando tudo em relatórios e um gráfico.

---

## 1. Objetivos

- Comparar G1GC, ZGC e ShenandoahGC sob **condições idênticas** de CPU/memória e carga.
- Mensurar **throughput (req/s)**, **latências (p50/p95/p99)** e **pausas de GC** (contagem, total, máximo e média).
- Fornecer um **pipeline automatizado** e reproduzível (build → warm‑up → medição → relatórios → gráfico).

---

## 2. Arquitetura e componentes

A aplicação é um serviço HTTP Java 25 com um endpoint de carga mista (`/work`) que combina alocação de objetos e CPU bound. Três instâncias idênticas executam a mesma aplicação, diferenciando apenas o GC.

| Serviço   | Porta | GC            |
|-----------|------:|---------------|
| app-g1    | 8081  | G1GC          |
| app-zgc   | 8082  | ZGC           |
| app-shen  | 8083  | ShenandoahGC  |

Componentes principais:

- `docker/Dockerfile`: build multi‑stage (Maven → Azul Zulu JDK 25).
- `docker/docker-compose.yml`: define os três serviços e portas.
- `scripts/run_service.sh`: inicialização da aplicação; recebe `GC`, `HEAP` e `JAVA_OPTS`.
- `scripts/run_burst.sh`: executa o teste de carga (tenta `wrk` local, depois `wrk` em container, por fim `curl`).
- `scripts/parse_gc_logs.py`: parse dos logs de GC gerados pelos containers.
- `scripts/merge_report.py`: une latência (wrk) + métricas de GC em `out/final_report.csv`.
- `scripts/plot_gc_results.py`: gera gráfico comparativo a partir do CSV final.
- `scripts/run_all.sh`: **pipeline único**: build → compose → limites de recursos → warm‑up → medição → relatórios → gráfico.
- `out/`: artefatos gerados (logs, CSVs, imagens).

---

## 3. Requisitos

- Docker Desktop (Compose V2).
- Bash (no Windows, usar Git Bash ou WSL).
- Python 3.9+ para processamento dos relatórios.
- Dependências Python para o gráfico (opcional): `pandas`, `matplotlib`.

Instalação das dependências opcionais:
```bash
pip install pandas matplotlib
```

---

## 4. Execução rápida (pipeline completo)

O script abaixo executa todo o fluxo de ponta a ponta:

```bash
./scripts/run_all.sh
```

O script realiza:
1. Build da imagem `poc-gc-java25` a partir de `docker/Dockerfile`.
2. Subida dos três containers via `docker/docker-compose.yml`.
3. Aplicação de **limites iguais** de CPU e memória em todos os serviços.
4. Verificação de readiness via `/health` (fallback em `/work?allocBytes=1`).
5. Limpeza de medições anteriores em `out/`.
6. **Warm‑up** (por padrão, 15 s; ajustável por variáveis).
7. **Medição principal** (por padrão, 45 s).
8. Parse de logs de GC e merge das métricas.
9. Geração do gráfico (se bibliotecas Python estiverem instaladas).

Ao final, os artefatos principais ficam em:
- `out/final_report.csv` — relatório consolidado de latência + GC
- `out/gc_report.csv` — métricas agregadas de GC
- `out/java25_gc_comparison.png` (+ `.svg`) — gráfico comparativo

---

## 5. Parâmetros e configuração

Os principais parâmetros são controlados por variáveis de ambiente ao invocar o `run_all.sh`:

- Limites de recursos (iguais para todos os serviços):
    - `LIMIT_CPUS` (padrão: `4`)
    - `LIMIT_MEM`  (padrão: `3g`)
- Warm‑up (fase 1):
    - `WARMUP_DUR`     (padrão: `15s`)
    - `WARMUP_THREADS` (padrão: `16`)
    - `WARMUP_CONN`    (padrão: `64`)
- Medição (fase 2):
    - `MEASURE_DUR`     (padrão: `45s`)
    - `MEASURE_THREADS` (padrão: `32`)
    - `MEASURE_CONN`    (padrão: `128`)
- Padrão de carga no endpoint `/work`:
    - `Q` (padrão: `allocBytes=4000000&cpuIters=200000&burstMs=50&sleepMs=5&payloadKb=1`)

Exemplos:
```bash
# Ajustando limites e carga
LIMIT_CPUS=2 LIMIT_MEM=2g MEASURE_DUR=60s MEASURE_THREADS=16 MEASURE_CONN=64 ./scripts/run_all.sh

# Aumentando “allocBytes” e “cpuIters”
Q="allocBytes=6000000&cpuIters=300000&burstMs=50&sleepMs=5&payloadKb=1" ./scripts/run_all.sh
```

Observações:
- O script tenta aplicar limites com `docker update --cpus/--memory`. Quando necessário, também define `--memory-swap` para igualar ao limite de memória.
- Alternativamente, os limites podem ser definidos no `docker-compose.yml` via `deploy.resources.limits` e subir com `docker compose --compatibility` (recomendado para reprodutibilidade declarativa).

---

## 6. Resultados de referência (exemplo)

Resultados observados recentemente (Java 25, heap 2 GB, 4 vCPUs/3 GB RAM por serviço, warm‑up de 15 s, medição de 45 s, 32 threads/128 conexões, carga mista no `/work`).

| GC          | Req/s | p50 (ms) | p95 (ms) | p99 (ms) | Coletas | Total pausa (ms) | Máx pausa (ms) | Média pausa (ms) |
|-------------|------:|---------:|---------:|---------:|--------:|-----------------:|---------------:|-----------------:|
| G1GC        |   924 |   155.88 |   192.92 |   210.42 |       2 |           12.444 |          7.011 |            6.222 |
| ZGC         |   897 |   157.37 |   197.17 |   213.39 |      25 |            0.308 |          0.018 |            0.012 |
| Shenandoah  |   916 |   155.58 |   189.90 |   206.46 |       5 |            6.048 |          1.890 |            1.210 |

Interpretação:
- Throughput semelhante entre os três; variações dependem do perfil de carga e recursos.
- Pausas médias de GC: **ZGC ≪ Shenandoah ≪ G1GC**.
- O warm‑up reduz dispersão e estabiliza as caudas (p99).

A tabela acima é um **exemplo**; gere seus próprios números executando o pipeline e consultando `out/final_report.csv`.

---

## 7. Estrutura do repositório

```
poc-shenandoahgc/
├── docker/
│   └── docker-compose.yml
├── scripts/
│   ├── merge_report.py
│   ├── parse_gc_logs.py
│   ├── plot_gc_results.py
│   ├── run_all.sh              # pipeline completo
│   ├── run_burst.sh
│   └── run_service.sh
├── src/                        # aplicação Java (endpoints e carga)
├── out/                        # artefatos gerados (CSV, logs, imagens)
└── README.md
```

---

## 8. Notas sobre ambiente e execução

- Windows:
    - Utilize **Git Bash** ou **WSL** para rodar os scripts `.sh`.
    - Caso use `wrk` via Docker, o script direciona os testes para `http://host.docker.internal`.
    - Em consoles com codificação CP1252, evite imprimir caracteres fora do ASCII em scripts Python (ou configure `PYTHONIOENCODING=utf-8`).

- wrk:
    - O `run_burst.sh` tenta, nesta ordem: `wrk` local, `wrk` em container, fallback `curl`.
    - O parse de métricas de latência depende do resumo JSON produzido por `wrk` ou do fallback gerado pelo script.

- Reprodutibilidade:
    - Para runs comparáveis, mantenha limites fixos de CPU/memória.
    - Execute medições múltiplas e considere médias/intervalos de confiança.

---

## 9. Troubleshooting

- `docker update: Memory limit should be smaller than memoryswap`  
  Solução: aplicar `--memory-swap` junto; o `run_all.sh` já faz a tentativa. Alternativa: declarar limites no compose e subir com `--compatibility`.
- `wrk` não encontrado / erros de console no Windows:  
  O script usa o runner em container ou fallback `curl`, e suprime dependência do `wrk` local.
- Gráfico não gerado:  
  Instale `pandas` e `matplotlib` e rode `python3 scripts/plot_gc_results.py`.

---

## 10. Licença

Este repositório é uma PoC educacional. Ajuste, reutilize e referencie conforme necessário no seu contexto de engenharia.
