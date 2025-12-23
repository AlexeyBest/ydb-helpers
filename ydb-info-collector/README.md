## Что это
Скрипт для сбора информации для диагностики проблем с инфраструктурой и настройками YDB.
## Что собирается
Собирается информация:
- Версия ОС, дистрибутив
- Информация о процессоре
- Информация о памяти
- Настройки ядра
- Информация о сервисах YDB
- Конфигурационный файл YDB
- Проверки YDB:
    - Healthcheck
    - Latency
    - Ping
## Как использовать
Нужно запускать скрипт с сервера, с которого есть доступ ко всем узлам YDB по ssh. Также на сервере нужно установить YDB CLI. 
- Открыть collect.sh, указать параметры:
    - `ssh_user`: пользователь для подключения к хостам через ssh.
    - `ydb_profile_name`: созданный профиль для подключения к YDB. Справка: [Создание профиля в YDB CLI](https://ydb.tech/docs/ru/reference/ydb-cli/profile/create)
    - `ydb_bin_path`: путь к YDB CLI ([Инструкция по установке YDB CLI](https://ydb.tech/docs/ru/reference/ydb-cli/install)).
- Отредактировать файл hosts.txt, перечислить хосты YDB. Список хостов нужен для подключения через SSH. Одна строчка - один хост.
- Сделать collect.sh исполняемым файлом:
    `chmod +x collect.sh`
- Запустить сбор информации:
    `./collect.sh`
- На выходе будет создан архив с собранной информацией, название будет вида: output_yyyymmdd_HHMMDD.tar.gz
## Что оценивать
В соответствии с рекомандациями [здесь](https://google.github.io/tcmalloc/tuning.html#system-level-optimizations):
- Файл host_{имя_хоста}_sysctl, параметр vm.overcommit_memory должен быть 1.
- Файл host_{имя_хоста}_thp, строки должны быть такими:
    - [always] madvise never
    - always defer [defer+madvise] madvise never
    - 0

Файл host_{имя_хоста}_cpugovernor: не должен быть включен режим PowerSave ([справка](https://www.kernel.org/doc/Documentation/cpu-freq/governors.txt)).

Не более 32 ядер на один процесс динноды [Документация YDB](https://ydb.tech/docs/ru/devops/concepts/system-requirements).

Установлены лимиты по памяти для процессов YDB. Лимиты могут устанавливаться в файле конфигурации сервиса (файл host_{имя_хоста}/service_{имя_сервиса}), могут конфигурации YDB (файл ydb_config.yaml). Сумма лимитов сервисов с одного сервера не должны превышать совокупный объём оперативной памяти на сервере (посмотреть можно в host_{имя_хоста}_memory). 

Ядро Linux должно быть версии 4.19+ [Документация YDB](https://ydb.tech/docs/ru/devops/concepts/system-requirements). Файл host_{имя_хоста}_uname.

Версия библиотеки libc должна быть 2.30+ [Документация YDB](https://ydb.tech/docs/ru/devops/concepts/system-requirements). Файл host_{имя_хоста}_libc_version.

Размер диска для данных не меньше 800 Гб [Документация YDB](https://ydb.tech/docs/ru/devops/concepts/system-requirements). Файл host_{имя_хоста}_lsblk.