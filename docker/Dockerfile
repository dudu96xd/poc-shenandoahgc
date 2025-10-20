FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /app
COPY . .
RUN mvn -q -DskipTests package

FROM azul/zulu-openjdk:25-latest
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
COPY scripts/run_service.sh /app/run_service.sh
RUN chmod +x /app/run_service.sh
RUN bash -lc 'java -XX:+UseShenandoahGC -version >/dev/null 2>&1 || (echo "Shenandoah indisponível nesta imagem" && exit 1)'
ENV HEAP=2g GC=shen
EXPOSE 8080
ENTRYPOINT ["/bin/bash","-lc","./run_service.sh"]
