# PoC — Comparativo de Garbage Collectors no Java 25
### Shenandoah GC × ZGC × G1GC

Este projeto avalia o desempenho dos principais coletores de lixo da JVM no Java 25, destacando as evoluções do **Shenandoah GC** — um coletor de baixa latência desenvolvido pela Red Hat e agora estável para produção.

---

## 1. Contexto

O **Shenandoah GC** é um coletor concorrente que realiza a maior parte do trabalho de coleta enquanto as aplicações continuam executando.  
O objetivo é reduzir significativamente as pausas de *stop-the-world*, tornando-o ideal para workloads sensíveis à latência.

O Shenandoah concorre diretamente com o **ZGC**, da Oracle, ambos priorizando pausas extremamente curtas e previsíveis.

| GC | Foco principal | Tempo típico de pausa | Disponível desde |
|----|----------------|-----------------------|------------------|
| G1GC | Equilíbrio entre throughput e pausas | 10–100 ms | Java 9 |
| ZGC | Pausas sub-milissegundo | < 1 ms | Java 15 |
| Shenandoah GC | Baixa latência adaptativa | ~1 ms | Java 25 (estável) |

---

## 2. Arquitetura da PoC

A aplicação é um microserviço em Java 25 que expõe um endpoint de carga controlável:

```
/work?allocBytes=4000000&cpuIters=200000&burstMs=50&sleepMs=5
```

Três containers idênticos executam a mesma aplicação, variando apenas o coletor de lixo:

| Container | Porta | GC |
|------------|--------|----|
| app-g1 | 8081 | G1GC |
| app-zgc | 8082 | ZGC |
| app-shen | 8083 | Shenandoah GC |

Cada instância utiliza:
```
-Xlog:gc*,safepoint=info
```
e um heap de 2 GB.

---

## 3. Estrutura do Projeto

| Diretório | Descrição |
|------------|------------|
| docker/Dockerfile | Build multi-stage (Maven → Azul Zulu JDK 25) |
| docker/docker-compose.yml | Executa os três containers simultaneamente |
| scripts/run_service.sh | Inicializa a aplicação com o GC configurado |
| scripts/run_burst.sh | Executa o benchmark com *wrk* (ou fallback curl) |
| scripts/parse_gc_logs.py | Analisa logs de GC e extrai métricas |
| scripts/merge_report.py | Consolida latência e GC em um CSV final |
| out/ | Contém logs, relatórios e gráficos gerados |

---

## 4. Runbook — Execução passo a passo

### 4.1 Build da imagem

```bash
docker build -f docker/Dockerfile -t poc-gc-java25 .
```

### 4.2 Subir containers

```bash
docker compose -f docker/docker-compose.yml up -d
docker ps --format "table {{.Names}}	{{.Ports}}"
```

Exemplo de saída esperada:
```
app-g1    0.0.0.0:8081->8080/tcp
app-zgc   0.0.0.0:8082->8080/tcp
app-shen  0.0.0.0:8083->8080/tcp
```

### 4.3 Executar o benchmark

```bash
chmod +x scripts/run_burst.sh
./scripts/run_burst.sh
```

O script tenta usar `wrk` localmente; se indisponível, executa via container.  
Os resultados são armazenados em `out/lat/`.

### 4.4 Gerar relatórios

```bash
python3 scripts/parse_gc_logs.py out
python3 scripts/merge_report.py
cat out/final_report.csv
```

### 4.5 Gerar gráfico comparativo

```bash
python3 scripts/plot_gc_results.py
```

---

## 5. Exemplo de Resultados

| GC | req/s | p99 (ms) | Média pausa GC (ms) |
|----|:------:|:---------:|:-------------------:|
| G1GC | 931 | 753.9 | 7.44 |
| ZGC | 870 | 894.1 | 0.014 |
| Shenandoah GC | 868 | 677.9 | 0.925 |

### Observações

- ZGC e Shenandoah eliminaram praticamente as pausas de GC.
- Shenandoah manteve throughput próximo ao G1, com latência muito menor.
- O p99 mais alto no ZGC veio da saturação de CPU, não do GC.

---

## 6. Gerar gráfico comparativo

Salve o script abaixo em `scripts/plot_gc_results.py`:

```python
import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv("out/final_report.csv")

plt.figure(figsize=(10, 6))
plt.style.use("dark_background")

bar_width = 0.25
x = range(len(df))
plt.bar([i - bar_width for i in x], df["req_per_sec"], width=bar_width, label="req/s (maior é melhor)", color="#4CAF50")
plt.bar(x, df["p99_ms"], width=bar_width, label="p99 latency (ms)", color="#FF9800")
plt.bar([i + bar_width for i in x], df["avg_pause_ms"], width=bar_width, label="avg GC pause (ms)", color="#03A9F4")

plt.xticks(x, df["gc"], fontsize=12)
plt.ylabel("Valores (escala relativa)", fontsize=12)
plt.title("Comparativo de GCs — Java 25 (2 GB heap, 32T/128C, 45 s)", fontsize=14, weight="bold")
plt.legend()
plt.grid(axis="y", alpha=0.2)

plt.tight_layout()
plt.savefig("out/java25_gc_comparison.png", dpi=300)
print("Gráfico salvo em: out/java25_gc_comparison.png")
```

---

## 7. Tecnologias Utilizadas

- Java 25 (Azul Zulu JDK 25)
- Docker / Docker Compose
- Maven 3.9+
- wrk (benchmark HTTP)
- Python 3 (pandas, matplotlib)
- Linux / Windows / WSL2

---

## 8. Referências

- [JEP 631 — Shenandoah GC: Stabilization and Enhancements (Java 25)](https://openjdk.org/jeps/631)
- [ZGC — Scalable Low-Latency GC](https://wiki.openjdk.org/display/zgc/Main)
- [Red Hat Developers — Shenandoah GC](https://developers.redhat.com/articles/2021/03/23/low-pause-garbage-collection-shenandoah)

---

## 9. Autor

**Igor Eduardo Troncoso Salvio**  
Senior Software Engineer | Java Performance & DevOps  
[github.com/dudu96xd](https://github.com/dudu96xd) • [linkedin.com/in/igortsalvio](https://www.linkedin.com/in/igortsalvio)
