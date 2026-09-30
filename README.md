# Домашнее задание: Настраиваемые бэкапы (borgbackup)

## Текст задания

Настроить стенд с двумя виртуальными машинами — **backup_server** и **client**.
Настроить удалённый бэкап каталога `/etc` с client при помощи **borgbackup**:

- директория для резервных копий `/var/backup` — отдельная точка монтирования (~2 GB);
- репозиторий зашифрован ключом или паролем;
- имя бэкапа содержит время снятия;
- глубина: год — по последней копии на конец месяца (кроме последних трёх месяцев); последние три месяца — копии на каждый день;
- резервная копия снимается каждые 5 минут (демонстрация);
- скрипт снятия бэкапов запускается из cron/systemd-таймера;
- логирование процесса бэкапа (вывод в `logger` с тегом; либо ротация при записи в файл).

Затем: запустить стенд на 30 минут, убедиться, что копии снимаются, остановить бэкап, переместить `/etc` и восстановить из бэкапа.

## Схема сети

| Роль | ВМ | ОС | IP |
|---|---|---|---|
| backup_server | **Hestia** (Proxmox VMID 105) | Ubuntu 24.04 | 192.168.1.157 |
| client | **Minerva** (Proxmox VMID 400) | Ubuntu 24.04 | 192.168.1.201 |

Связь: client → backup по SSH (пользователь `borg`), репозиторий `borg@192.168.1.157:/var/backup/`.

## Выполнение

### 1. backup_server (Hestia)

- Добавлен отдельный диск 2 GB (`qm set 105 -scsi1 purple:2`) → `/dev/sdb` → раздел `/dev/sdb1` (ext4) смонтирован в `/var/backup` через fstab по UUID (`nofail`).
- Пользователь `borg`, каталог `/var/backup` принадлежит `borg:borg`.
- В `~borg/.ssh/authorized_keys` добавлены публичные ключи (adrianl@minerva и root@minerva).

```bash
df -h /var/backup
# /dev/sdb1  2.0G  24K  1.9G  1% /var/backup
```

### 2. client (Minerva)

- Установлен `borgbackup` (1.2.8).
- Ключ root@minerva авторизован на backup (сервис работает от root).
- Инициализация репозитория (шифрование **repokey**, пароль `Otus1234`):

```bash
BORG_NEW_PASSPHRASE='Otus1234' borg init --encryption=repokey borg@192.168.1.157:/var/backup/
```

### 3. Скрипт бэкапа `/usr/local/bin/borg-backup.sh`

```bash
export BORG_PASSPHRASE='Otus1234'
REPO="borg@192.168.1.157:/var/backup/"
exec > >(logger -t "borg-backup") 2>&1

borg create --stats --compression zstd "${REPO}::etc-{now:%Y-%m-%d_%H:%M:%S}" /etc
borg check  "${REPO}"
borg prune --stats --keep-daily 90 --keep-monthly 12 --keep-yearly 1 "${REPO}"
```

- **Имя бэкапа** — `etc-{now:%Y-%m-%d_%H:%M:%S}` (содержит время снятия).
- **Политика хранения** (`prune`): `--keep-daily 90` (последние 3 месяца — ежедневно) + `--keep-monthly 12` (по копии на конец месяца за год) + `--keep-yearly 1` (глубина — год).
- **Логирование** — весь вывод через `logger -t borg-backup` (виден в `journalctl -t borg-backup`), т.е. в syslog (ротация не требуется).

### 4. systemd timer (каждые 5 минут)

`borg-backup.service` (Type=oneshot) + `borg-backup.timer` (`OnUnitActiveSec=5min`), включён:

```bash
systemctl list-timers borg-backup.timer
# NEXT Wed 2026-09-30 07:39:03 UTC ... borg-backup.timer borg-backup.service
```

### 5. Проверка (стенд гонялся ~30 минут)

```bash
borg list borg@192.168.1.157:/var/backup/
# etc-2026-09-30_07:34:03   ...
```

Логи процесса: `journalctl -t borg-backup` — начало/конец каждого прогона, статистика create/prune.

### 6. Восстановление из бэкапа

Полный цикл по ТЗ (остановка бэкапа → перемещение `/etc` → восстановление):

```bash
systemctl stop borg-backup.timer
# распаковка актуального архива во временный каталог (пока /etc на месте)
cd /tmp/etc-restore && borg extract borg@.../var/backup/::etc-2026-... 
mv /etc /etc.orig
cp -a /tmp/etc-restore/etc /etc
# проверка: passwd/hostname/fstab на месте, содержимое совпадает с оригиналом
systemctl start borg-backup.timer
```

## Файлы репозитория

| Файл | Назначение |
|---|---|
| `Vagrantfile` | Стенд из 2 ВМ + запуск ansible-плейбука |
| `ansible/playbook.yml` | Установка borgbackup, пользователь/каталог на backup, скрипт и таймер на client |
| `borg-backup.sh` | Скрипт снятия бэкапов (create + check + prune + logger) |
| `borg-backup.service`, `borg-backup.timer` | systemd unit и таймер (5 мин) |

## Заметки

- Состояние borg (`/var/backup`) лежит на отдельном диске 2 GB.
- Таймер `OnUnitActiveSec=5min` даёт интервал ровно 5 минут между запусками после первого.
