# Примеры интеграции проектов

Этот каталог содержит примеры и инструкции по интеграции проектов с системой мониторинга.

## Файлы

- `servicemonitor-example.yaml` - Пример ServiceMonitor для Django приложения
- `integration-guide.md` - Подробная инструкция по интеграции

## Быстрый старт

1. Скопируйте `servicemonitor-example.yaml` в ваш проект
2. Замените `myproject` на имя вашего проекта
3. Настройте labels в вашем Service
4. Примените манифест: `kubectl apply -f servicemonitor-example.yaml`

## Дополнительная документация

См. `integration-guide.md` для подробных инструкций.
