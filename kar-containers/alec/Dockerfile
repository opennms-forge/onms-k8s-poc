FROM alpine
RUN mkdir -p /plugins
RUN VERSION=$(wget -O -  https://api.github.com/repos/OpenNMS/alec/releases/latest 2>/dev/null | grep tag_name | cut -d '"' -f 4) && \
    wget -O /plugins/opennms-alec-plugin.kar https://github.com/OpenNMS/alec/releases/download/$VERSION/opennms-alec-plugin.kar