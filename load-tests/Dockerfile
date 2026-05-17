FROM locustio/locust:latest

COPY locustfile.py /mnt/locust/locustfile.py

WORKDIR /mnt/locust

EXPOSE 8089

ENTRYPOINT ["locust"]
