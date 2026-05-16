FROM locustio/locust:2.40

COPY locustfile.py /mnt/locust/locustfile.py

WORKDIR /mnt/locust

EXPOSE 8089

ENTRYPOINT ["locust"]
