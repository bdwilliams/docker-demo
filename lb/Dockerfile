FROM ubuntu:14.04

RUN apt-get update && \
	apt-get install curl unzip nginx -y
ADD start.sh /opt/start.sh
RUN chmod +x /opt/start.sh
ADD nginx.template /opt/nginx.template
RUN cd /usr/local/bin && \
	curl -sSL https://releases.hashicorp.com/consul-template/0.14.0/consul-template_0.14.0_linux_amd64.zip > tmp.zip && \
	unzip tmp.zip && rm -rf tmp.zip

EXPOSE 80 8080
CMD ["/opt/start.sh"]