FROM ruby:2.7

RUN apt-get update -qq \
    && apt-get install -qqy \
        easy-rsa \
        git \
    && ln -s /usr/share/easy-rsa/easyrsa  /usr/bin/

ENV EASYRSA=/usr/share/easy-rsa
ENV EASYRSA_BATCH=yes

ARG CFNVPN_VERSION="1.5.0"

COPY . /src

WORKDIR /src

RUN gem build cfn-vpn.gemspec \
    && gem install cfn-vpn-${CFNVPN_VERSION}.gem \
    && rm -rf /src

RUN addgroup --gid 1000 cfnvpn && \
    adduser --home /home/cfnvpn --uid 1000 --disabled-password --gecos GECOS --gid 1000 cfnvpn

USER cfnvpn

RUN cfndsl -u 9.0.0