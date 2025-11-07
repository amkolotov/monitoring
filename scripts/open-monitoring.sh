#!/bin/bash
# Открытие мониторинга в браузере

DOMAIN=${DOMAIN:-example.com}
NAMESPACE=${MONITORING_NAMESPACE:-monitoring}

GRAFANA_URL="https://grafana.${DOMAIN}"
PROMETHEUS_URL="https://prometheus.${DOMAIN}"
PORTAINER_URL="https://portainer.${DOMAIN}"

echo "📊 Monitoring Services:"
echo "   Grafana:    ${GRAFANA_URL}"
echo "   Prometheus: ${PROMETHEUS_URL}"
echo "   Portainer:  ${PORTAINER_URL}"

# Открываем в браузере
if [ "$1" == "open" ]; then
  if command -v xdg-open &> /dev/null; then
    xdg-open "$GRAFANA_URL" 2>/dev/null
  elif command -v open &> /dev/null; then
    open "$GRAFANA_URL" 2>/dev/null
  else
    echo "Не удалось открыть браузер автоматически"
  fi
fi
