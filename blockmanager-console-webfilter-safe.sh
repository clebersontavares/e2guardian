#!/bin/sh
# Block Manager 
# Backup completo auto-instalavel: gera snapshot + install.sh dentro do .tar.gz
#
# Uso:
#   sh blockmanager-console.sh
#   sh blockmanager-console.sh /root/dnsmanager-backups
#   sh blockmanager-console.sh --mode 1 /root/dnsmanager-backups
#   sh blockmanager-console.sh --mode 2 /root/dnsmanager-backups
#   sh blockmanager-console.sh --mode 3 /root/dnsmanager-backups
#   sh blockmanager-console.sh --dry-run --mode 3
#
# Modos:
#   1 = aplicacao + configuracoes/politicas
#   2 = modo 1 + usuarios/identidades
#   3 = completo: modo 2 + sessoes, historicos, caches e logs
#
# O pacote sempre preserva config.xml, cron e filter.inc em reference/ para auditoria,
# mas o install.sh NUNCA os restaura automaticamente.
# O E2Guardian nativo e instalado manualmente e nunca e empacotado.
# Chaves privadas, configuracoes geradas, PIDs e arquivos sensiveis de runtime
# nunca entram no payload: o proprio Block Manager os materializa no destino.
set -eu
umask 077

VERSION="stable"
DRY_RUN=0
MODE=""
DEST_ROOT="/root/dnsmanager-backups"

usage() {
    cat <<EOF
Uso: sh $(basename "$0") [--dry-run] [--mode 1|2|3] [diretorio_destino]

  --dry-run     somente inventaria; nao cria o pacote
  --mode 1      aplicacao + configuracoes/politicas
  --mode 2      modo 1 + usuarios/identidades
  --mode 3      completo: modo 2 + sessoes/historicos/caches/logs
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --mode)
            shift
            [ "$#" -gt 0 ] || { echo "ERRO: --mode exige 1, 2 ou 3." >&2; exit 2; }
            MODE="$1"
            ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "ERRO: opcao invalida: $1" >&2; usage >&2; exit 2 ;;
        *) DEST_ROOT="$1" ;;
    esac
    shift
done

if [ "$(id -u)" != "0" ]; then
    echo "ERRO: execute como root." >&2
    exit 1
fi

if [ -z "$MODE" ]; then
    cat <<'EOF'
============================================================
 BLOCK MANAGER - GERADOR DE BACKUP 
============================================================

Selecione o conteudo do pacote:

  1) Aplicacao + configuracoes/politicas [RECOMENDADO]
     Sem usuarios, sessoes, relatorios, caches ou logs.

  2) Aplicacao + configuracoes/politicas + usuarios
     Inclui identidades persistidas.
     Sem sessoes, relatorios, caches ou logs.

  3) Completo
     Inclui aplicacao, configuracoes, usuarios, sessoes,
     relatorios, caches e logs existentes.

EOF
    printf "Opcao [1]: "
    read -r MODE || MODE=""
    MODE="${MODE:-1}"
fi
case "$MODE" in 1|2|3) ;; *) echo "ERRO: modo invalido: $MODE" >&2; exit 2 ;; esac

STAMP="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname 2>/dev/null || echo firewall)"
NAME="BlockManager--${HOST}-${STAMP}"
WORK="${DEST_ROOT}/.${NAME}.work"
PKG="$WORK/$NAME"
PAYLOAD="$PKG/payload"
REFERENCE="$PKG/reference"
MANIFEST="$PKG/manifest"
ARCHIVE="${DEST_ROOT}/${NAME}.tar.gz"
SHA_FILE="${ARCHIVE}.sha256"

cleanup() {
    [ -d "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

manifest_line() {
    status="$1"; category="$2"; path="$3"; scope="$4"
    if [ "$DRY_RUN" = "1" ]; then
        printf '%s;%s;%s;%s\n' "$status" "$category" "$scope" "$path"
    else
        printf '%s;%s;%s;%s\n' "$status" "$category" "$scope" "$path" >> "$MANIFEST/ITENS.csv"
    fi
}

copy_payload() {
    src="$1"; label="$2"; minmode="$3"
    if [ "$MODE" -lt "$minmode" ]; then
        manifest_line IGNORADO "$label" "$src" "modo<$minmode"
        return 0
    fi
    if [ ! -e "$src" ]; then
        manifest_line AUSENTE "$label" "$src" payload
        return 0
    fi
    manifest_line OK "$label" "$src" payload
    [ "$DRY_RUN" = "1" ] && return 0
    target="$PAYLOAD$src"
    mkdir -p "$(dirname "$target")"
    rm -rf "$target"
    cp -Rp "$src" "$target"
}

copy_reference() {
    src="$1"; label="$2"
    if [ ! -e "$src" ]; then
        manifest_line AUSENTE "$label" "$src" reference
        return 0
    fi
    manifest_line OK "$label" "$src" reference
    [ "$DRY_RUN" = "1" ] && return 0
    target="$REFERENCE$src"
    mkdir -p "$(dirname "$target")"
    rm -rf "$target"
    cp -Rp "$src" "$target"
}

copy_payload_tree_safe() {
    src="$1"; label="$2"; minmode="$3"
    if [ "$MODE" -lt "$minmode" ]; then manifest_line IGNORADO "$label" "$src" "modo<$minmode"; return 0; fi
    if [ ! -d "$src" ]; then manifest_line AUSENTE "$label" "$src" payload; return 0; fi
    find "$src" -type f -print | sort | while IFS= read -r file; do
        rel="${file#$src/}"
        case "$rel" in
            private/*|generated/*|*.key|*.p12|*.pfx|*.pid|*.lock)
                manifest_line SENSIVEL "$label" "$file" "regenerado-no-destino"; continue ;;
        esac
        manifest_line OK "$label" "$file" payload
        [ "$DRY_RUN" = "1" ] && continue
        target="$PAYLOAD$file"; mkdir -p "$(dirname "$target")"; cp -p "$file" "$target"
    done
}

collect_items() {
    # Aplicacao WebGUI / DNS / Firewall / Captive
    copy_payload /usr/local/www/block_manager.php WEBGUI 1
    copy_payload /usr/local/www/categories_manager.php WEBGUI 1
    copy_payload /usr/local/www/filter_manager.php WEBGUI_FIREWALL 1
    copy_payload /usr/local/www/dnsmanager APLICACAO_DNS_FIREWALL 1
    copy_payload /usr/local/www/dnsmanager_portal.php PORTAL_WEB 1
    copy_payload /usr/local/www/dnsmanager_portal_logo.php PORTAL_WEB 1
    copy_payload /usr/local/www/dnsmanager-http-router.php PORTAL_HTTP 1
    copy_payload /usr/local/www/dnsmanager-http-service.php PORTAL_HTTP_LEGADO 1

    # Workers proprios. Nao copia /usr/local/sbin inteiro.
    copy_payload /usr/local/sbin/dnsmanager-worker.php WORKER_DNS 1
    for f in /usr/local/sbin/dnsmanager-* /usr/local/sbin/*dnsmanager*; do
        [ -e "$f" ] || continue
        [ "$f" = "/usr/local/sbin/dnsmanager-worker.php" ] && continue
        case "$f" in *dnsmanager-backup-v*.sh) continue ;; esac
        copy_payload "$f" WORKER_AUXILIAR 1
    done
    copy_payload /usr/local/sbin/filter-manager-worker.php WORKER_FIREWALL 1
    copy_payload /usr/local/sbin/suricata_manager_worker.php WORKER_SURICATA 1
    copy_payload /usr/local/etc/dnsmanager-captive-portal.json CAPTIVE_CONFIG 1

    # Web Filter: codigo, controladores e rc.d proprios.
    copy_payload /usr/local/www/blockmanager-webfilter WEBFILTER_WEBGUI 1
    for f in /usr/local/sbin/blockmanager-webfilter-*; do [ -e "$f" ] || continue; copy_payload "$f" WEBFILTER_BACKEND 1; done
    for f in /usr/local/etc/rc.d/blockmanager-webfilter*; do [ -e "$f" ] || continue; copy_payload "$f" WEBFILTER_RCD 1; done

    # Configuracao declarativa. private/ e generated/ sao sempre regenerados no destino.
    copy_payload_tree_safe /usr/local/etc/blockmanager/webfilter WEBFILTER_CONFIG 1
    copy_payload_tree_safe /var/db/blockmanager/webfilter WEBFILTER_STATE 2
    copy_payload /var/log/blockmanager/webfilter WEBFILTER_LOGS 3
    copy_payload /var/log/e2guardian WEBFILTER_E2GUARDIAN_LOGS 3

    # Estado declarativo. Mantemos /var/unbound/lists como baseline do produto.
    # O install.sh decide o subconjunto restaurado de acordo com o modo gravado.
    copy_payload /var/unbound/lists CONFIGURACAO_DNSMANAGER 1

    # Configuracao do Filter Manager fica sob /var/log, mas e declarativa.
    copy_payload /var/log/dnsfilter/filter/settings.json FILTER_CONFIG 1
    copy_payload /var/log/dnsfilter/filter/service_registry.json FILTER_SERVICOS 1
    copy_payload /var/log/dnsfilter/filter/service-categories FILTER_CATEGORIAS 1

    # Logs/historicos somente modo completo.
    copy_payload /var/log/dnsfilter LOGS_DNSMANAGER 3
    copy_payload /var/log/dnsfilter-manager.log LOGS_DNSMANAGER 3
    copy_payload /var/log/resolver.log LOG_RESOLVER 3
    copy_payload /var/backups/dnsmanager BACKUPS_INTERNOS 3

    # Referencias: preservadas no arquivo, mas deliberadamente fora do payload.
    copy_reference /conf/config.xml PFSENSE_CONFIG
    copy_reference /etc/crontab AGENDAMENTO
    copy_reference /var/cron/tabs/root AGENDAMENTO
    copy_reference /var/unbound/unbound.conf UNBOUND_REFERENCIA
    copy_reference /var/unbound/unbound.conf.d UNBOUND_REFERENCIA
    copy_reference /etc/inc/filter.inc PFSENSE_FILTER_GENERATOR
}

write_installer() {
cat > "$PKG/install.sh" <<'INSTALL'
#!/bin/sh
# Block Manager - instalador/update seguro do pacote auto-instalavel
# NUNCA apaga arvores do pfSense. NUNCA restaura config.xml ou cron.
set -eu
umask 022

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PAYLOAD="$SCRIPT_DIR/payload"
MANIFEST="$SCRIPT_DIR/manifest"
PHP_BIN="/usr/local/bin/php"
STAMP="$(date +%Y%m%d-%H%M%S)"
LIST="/tmp/dnsmanager-install-$$.lst"
SELECTED="/tmp/dnsmanager-selected-$$.lst"
trap 'rm -f "$LIST" "$SELECTED"' EXIT INT TERM

fail(){ echo "ERRO: $*" >&2; exit 1; }
[ "$(id -u)" = "0" ] || fail "execute como root."
[ -d "$PAYLOAD" ] || fail "payload nao encontrado: $PAYLOAD"
[ -x "$PHP_BIN" ] || fail "PHP nao encontrado em $PHP_BIN"

BACKUP_VERSION="desconhecida"
BACKUP_MODE=1
[ -f "$MANIFEST/PACOTE.conf" ] && . "$MANIFEST/PACOTE.conf"

# Detecta versao instalada apenas para exibir. Nao bloqueia update por heuristica.
detect_installed_version(){
    for f in /usr/local/www/block_manager.php /usr/local/www/dnsmanager/includes/core.php /usr/local/www/dnsmanager_portal.php; do
        [ -f "$f" ] || continue
        v="$(grep -Eio '(File-Version|VERSION|DNS Manager)[^0-9V]*V?[0-9]+\.[0-9]+(\.[0-9]+)?([.-][A-Za-z0-9]+)*' "$f" 2>/dev/null | head -1 | sed -E 's/.*[Vv]?([0-9]+\.[0-9]+(\.[0-9]+)?([.-][A-Za-z0-9]+)*).*/\1/' || true)"
        [ -n "$v" ] && { echo "$v"; return 0; }
    done
    echo "nao identificada"
}
INSTALLED_VERSION="$(detect_installed_version)"

cat <<EOF
============================================================
 BLOCK MANAGER - INSTALL / UPDATE
============================================================
Versao instalada : $INSTALLED_VERSION
Versao do pacote : $BACKUP_VERSION

Selecione a operacao:

  1) UPDATE DE VERSAO [RECOMENDADO]
     Atualiza somente codigo da aplicacao, workers e assets.
     Preserva configuracoes, grupos, usuarios, conectores, politicas,
     aliases, sessoes, relatorios, caches e logs do firewall destino.

  2) RESTAURAR APLICACAO + CONFIGURACOES/POLITICAS
     Copia codigo + configuracoes/politicas existentes no pacote.
     Nao restaura usuarios nem dados operacionais.

  3) RESTAURAR APLICACAO + CONFIGURACOES + USUARIOS
     Inclui usuarios/dispositivos/identidades persistidas.
     Nao restaura sessoes, relatorios, caches ou logs.

  4) RESTAURACAO COMPLETA
     Copia tudo que estiver no payload do pacote.

  5) APAGAR / DESINSTALAR BLOCK MANAGER [SEGURO]
     Faz backup dos arquivos atuais antes de remover.
     Remove somente arquivos identificados como pertencentes ao Block Manager.
     NUNCA remove /usr/local/www, /usr/local/sbin, /var/unbound ou /var/log.

EOF
printf "Opcao [1]: "
read -r OP || OP=""
OP="${OP:-1}"
case "$OP" in 1|2|3|4|5) ;; *) fail "opcao invalida: $OP" ;; esac

is_never_install(){
    case "$1" in
        /conf/*|/etc/crontab|/etc/inc/*|/var/cron/*) return 0 ;;
        /usr/local/sbin/unbound|/usr/local/sbin/unbound-*|/usr/local/sbin/sshguard|/usr/local/sbin/php*|/usr/local/sbin/pfctl) return 0 ;;
    esac
    return 1
}

is_application(){
    case "$1" in
        /usr/local/www/dnsmanager/*|/usr/local/www/blockmanager-webfilter/*|/usr/local/www/block_manager.php|/usr/local/www/categories_manager.php|/usr/local/www/filter_manager.php|/usr/local/www/dnsmanager_portal.php|/usr/local/www/dnsmanager_portal_logo.php|/usr/local/www/dnsmanager-http-router.php|/usr/local/www/dnsmanager-http-service.php|/usr/local/sbin/dnsmanager-*|/usr/local/sbin/blockmanager-webfilter-*|/usr/local/sbin/filter-manager-worker.php|/usr/local/sbin/suricata_manager_worker.php|/usr/local/etc/rc.d/blockmanager-webfilter*|/usr/local/etc/blockmanager/webfilter/*|/usr/local/etc/dnsmanager-captive-portal.json) return 0 ;;
    esac
    return 1
}

is_user_data(){
    case "$1" in
        /var/unbound/lists/users/*|/var/unbound/lists/devices/*|/var/unbound/lists/networks/*|/var/unbound/lists/device-bindings/*|/var/unbound/lists/presence/*|/var/unbound/lists/portal/users.json|/var/unbound/lists/portal/bindings*) return 0 ;;
    esac
    return 1
}

is_runtime(){
    case "$1" in
        /var/unbound/lists/portal/sessions.json|/var/unbound/lists/*cache*|/var/unbound/lists/*cache*/*|/var/unbound/lists/report-cache/*|/var/unbound/lists/reports/*|/var/unbound/lists/*history*|/var/unbound/lists/*history*/*|/var/unbound/lists/online*|/var/unbound/lists/online*/*|/var/log/*|*.csv) return 0 ;;
    esac
    return 1
}

should_install(){
    p="$1"
    is_never_install "$p" && return 1
    # UPDATE: exclusivamente codigo/workers/assets. Nenhum estado/config do destino.
    if [ "$OP" = "1" ]; then is_application "$p"; return $?; fi
    is_application "$p" && return 0
    case "$p" in
        /var/db/blockmanager/webfilter/*) [ "$OP" = "3" ] || [ "$OP" = "4" ]; return $? ;;
        /var/unbound/lists/*)
            if is_runtime "$p"; then [ "$OP" = "4" ]; return $?; fi
            if is_user_data "$p"; then [ "$OP" = "3" ] || [ "$OP" = "4" ]; return $?; fi
            # Configuracoes/politicas DNS e Firewall entram nos modos 2-4.
            return 0
            ;;
        /var/log/*) [ "$OP" = "4" ]; return $? ;;
    esac
    return 1
}

if [ "$OP" = "5" ]; then
    REMOVE_BACKUP="/root/blockmanager-preremove-${STAMP}"
    mkdir -p "$REMOVE_BACKUP"
    echo ""
    echo "REMOCAO SEGURA DO BLOCK MANAGER"
    echo "Backup: $REMOVE_BACKUP"
    echo "Diretorios do sistema NAO serao removidos."
    REMOVE_LIST="/tmp/dnsmanager-remove-$$.lst"
    trap 'rm -f "$LIST" "$SELECTED" "$REMOVE_LIST"' EXIT INT TERM
    find "$PAYLOAD" -type f -print | sort | while IFS= read -r src; do
        rel="${src#$PAYLOAD}"
        if is_application "$rel"; then echo "$rel"; fi
    done > "$REMOVE_LIST"
    while IFS= read -r dst; do
        [ -f "$dst" ] || continue
        mkdir -p "$REMOVE_BACKUP$(dirname "$dst")"
        cp -p "$dst" "$REMOVE_BACKUP$dst"
        rm -f "$dst"
        echo "[REMOVIDO] $dst"
    done < "$REMOVE_LIST"
    echo ""
    echo "Remocao concluida. Backup: $REMOVE_BACKUP"
    echo "Nenhum diretorio-base do pfSense foi apagado."
    exit 0
fi

find "$PAYLOAD" -type f -print | sort > "$LIST"
: > "$SELECTED"
echo ""
echo "Arquivos selecionados:"
while IFS= read -r src; do
    rel="${src#$PAYLOAD}"
    if should_install "$rel"; then
        echo "[COPIAR]  $rel"
        echo "$src" >> "$SELECTED"
    else
        echo "[PRESERVAR/IGNORAR] $rel"
    fi
done < "$LIST"
[ -s "$SELECTED" ] || fail "nenhum arquivo elegivel para a operacao selecionada."

# Valida absolutamente todos os PHP selecionados ANTES de alterar o host.
echo ""
echo "Validando PHP antes da copia..."
while IFS= read -r src; do
    case "$src" in *.php) "$PHP_BIN" -l "$src" >/dev/null || fail "PHP invalido no pacote: ${src#$PAYLOAD}" ;; esac
done < "$SELECTED"

case "$OP" in
    1) ROLLBACK_DIR="/root/dnsmanager-preupdate-${STAMP}" ;;
    *) ROLLBACK_DIR="/root/dnsmanager-preinstall-${STAMP}" ;;
esac
mkdir -p "$ROLLBACK_DIR"
COPIED=0; UPDATED=0; NEW=0; BACKED_UP=0; FAILED=0

echo ""
echo "Backup de rollback: $ROLLBACK_DIR"
echo "Copiando arquivo por arquivo. Nenhum diretorio existente sera apagado."
echo "Politica segura: somente mkdir -p + cp por arquivo; sem rm -rf no destino."
while IFS= read -r src; do
    rel="${src#$PAYLOAD}"
    dst="$rel"
    if [ -f "$dst" ]; then
        mkdir -p "$ROLLBACK_DIR$(dirname "$dst")"
        cp -p "$dst" "$ROLLBACK_DIR$dst"
        BACKED_UP=$((BACKED_UP + 1))
        STATUS="ATUALIZADO"
        UPDATED=$((UPDATED + 1))
    else
        STATUS="NOVO"
        NEW=$((NEW + 1))
    fi
    mkdir -p "$(dirname "$dst")"
    if cp -p "$src" "$dst"; then
        COPIED=$((COPIED + 1))
        echo "[$STATUS] $dst"
    else
        FAILED=$((FAILED + 1))
        echo "[FALHA] $dst" >&2
    fi
done < "$SELECTED"
[ "$FAILED" -eq 0 ] || fail "$FAILED arquivo(s) falharam. Rollback: $ROLLBACK_DIR"

# Checagem pos-copia por hash/tamanho.
echo ""
echo "Check pos-copia..."
while IFS= read -r src; do
    rel="${src#$PAYLOAD}"; dst="$rel"
    [ -f "$dst" ] || fail "arquivo nao encontrado apos copia: $dst"
    if command -v sha256 >/dev/null 2>&1; then
        [ "$(sha256 -q "$src")" = "$(sha256 -q "$dst")" ] || fail "hash divergente: $dst"
    else
        [ "$(wc -c < "$src")" = "$(wc -c < "$dst")" ] || fail "tamanho divergente: $dst"
    fi
    case "$dst" in *.php) "$PHP_BIN" -l "$dst" >/dev/null || fail "PHP instalado invalido: $dst" ;; esac
    echo "[OK] $dst"
done < "$SELECTED"

# Normaliza somente permissoes dos arquivos proprios do Web Filter.
for f in /usr/local/sbin/blockmanager-webfilter-*; do [ -f "$f" ] || continue; chown root:wheel "$f"; chmod 0750 "$f"; done
[ ! -f /usr/local/sbin/blockmanager-webfilter-pf-root.php ] || chmod 0755 /usr/local/sbin/blockmanager-webfilter-pf-root.php
for f in /usr/local/etc/rc.d/blockmanager-webfilter*; do [ -f "$f" ] || continue; chown root:wheel "$f"; chmod 0755 "$f"; done

if [ -x /usr/local/sbin/e2guardian ]; then
    echo "[OK] E2Guardian nativo encontrado."
else
    echo "ALERTA: E2Guardian nativo nao encontrado; instale manualmente antes de ativar o Web Filter." >&2
fi
echo "[PRESERVADO] /etc/inc/filter.inc, config.xml e cron"
echo "[REGERAR] CA/chaves e configuracao generated/ do Web Filter"

# Apenas valida Unbound. Nunca substitui binario e nunca reinicia automaticamente.
if [ -x /usr/local/sbin/unbound-checkconf ] && [ -f /var/unbound/unbound.conf ]; then
    /usr/local/sbin/unbound-checkconf /var/unbound/unbound.conf || echo "ALERTA: unbound-checkconf falhou; nenhum servico foi reiniciado." >&2
fi

echo ""
echo "============================================================"
echo " OPERACAO CONCLUIDA"
echo "============================================================"
case "$OP" in
  1) echo "Operacao: UPDATE DE VERSAO" ;;
  2) echo "Operacao: RESTORE APLICACAO + CONFIGURACOES" ;;
  3) echo "Operacao: RESTORE + USUARIOS" ;;
  4) echo "Operacao: RESTORE COMPLETO" ;;
  5) echo "Operacao: REMOCAO SEGURA" ;;
esac
echo "Versao anterior detectada: $INSTALLED_VERSION"
echo "Versao do pacote:           $BACKUP_VERSION"
echo "Arquivos copiados:          $COPIED"
echo "Arquivos atualizados:       $UPDATED"
echo "Arquivos novos:             $NEW"
echo "Arquivos preservados:       $BACKED_UP"
echo "Rollback:                   $ROLLBACK_DIR"
echo ""
echo "config.xml: NAO aplicado"
echo "cron:       NAO aplicado"
echo "servicos:   NAO reiniciados automaticamente"
if [ "$OP" = "1" ]; then
    echo ""
    echo "UPDATE preservou os dados/configuracoes existentes do firewall destino."
fi
INSTALL
chmod 750 "$PKG/install.sh"
}

if [ "$DRY_RUN" = "1" ]; then
    echo "Block Manager  - dry-run - modo ${MODE}"
    echo "Nenhum arquivo sera copiado e nenhum servico sera alterado."
    echo "status;categoria;escopo;caminho"
    collect_items
    exit 0
fi

mkdir -p "$DEST_ROOT"
rm -rf "$WORK"
mkdir -p "$PAYLOAD" "$REFERENCE" "$MANIFEST"
printf 'status;categoria;escopo;caminho\n' > "$MANIFEST/ITENS.csv"
printf 'BACKUP_VERSION=%s\nBACKUP_MODE=%s\nBACKUP_HOST=%s\nBACKUP_CREATED=%s\n' \
    "$VERSION" "$MODE" "$HOST" "$STAMP" > "$MANIFEST/PACOTE.conf"

collect_items
write_installer

cat > "$PKG/README.txt" <<EOF
Block Manager  - backup auto-instalavel
Host de origem: ${HOST}
Gerado em: $(date '+%Y-%m-%d %H:%M:%S %z')
Modo: ${MODE}

Estrutura:
  install.sh   instalador seguro do payload
  payload/     arquivos do produto aptos a restauracao automatica
  reference/   config.xml, cron e Unbound somente para referencia/auditoria
  manifest/    inventario, ambiente e hashes

Para instalar em outro pfSense:
  tar -xzf ${NAME}.tar.gz
  cd ${NAME}
  sh install.sh

IMPORTANTE:
- install.sh nao restaura config.xml nem cron.
- install.sh nao instala o E2Guardian nem binarios nativos do pfSense.
- install.sh nunca restaura /etc/inc/filter.inc, config.xml ou cron.
- CA, chaves privadas e generated/ do Web Filter sao regenerados no destino.
- install.sh cria backup pre-instalacao apenas dos arquivos que sobrescrevera.
- nenhum servico e reiniciado ou ativado automaticamente.
EOF

{
    echo "Block Manager  - inventario"
    echo "Gerado em: $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Host: ${HOST}"
    echo "Modo: ${MODE}"
    echo "Kernel: $(uname -a 2>/dev/null || true)"
    echo
    echo "== Processos Block Manager / Web Filter / DNS / Firewall / Suricata =="
    ps auxww 2>/dev/null | grep -E 'blockmanager-webfilter|e2guardian|dnsmanager|filter-manager|suricata|unbound' | grep -v grep || true
    echo
    echo "== Portas em escuta =="
    sockstat -4 -l 2>/dev/null || true
    echo
    echo "== Cron relacionado =="
    grep -RinE 'blockmanager-webfilter|e2guardian|dnsmanager|filter-manager|suricata' /etc/crontab /var/cron/tabs 2>/dev/null || true
} > "$MANIFEST/RELATORIO-AMBIENTE.txt"

# Valida todos os PHP copiados antes de fechar o backup.
PHP_BIN="/usr/local/bin/php"
if [ -x "$PHP_BIN" ]; then
    find "$PAYLOAD" -type f -name '*.php' -print | sort | while IFS= read -r f; do
        "$PHP_BIN" -l "$f" >/dev/null || { echo "ERRO: PHP invalido no snapshot: $f" >&2; exit 1; }
    done
fi

# SHA-256 interno, incluindo install.sh, payload, reference e manifest.
(
    cd "$PKG"
    find . -type f ! -path './manifest/SHA256SUMS' -print | sort | while IFS= read -r file; do
        sha256 -q "$file" | awk -v f="$file" '{print $1 "  " f}'
    done
) > "$MANIFEST/SHA256SUMS"

# Compactacao atomica do diretorio raiz, para que install.sh fique dentro do pacote.
TMP_ARCHIVE="${ARCHIVE}.tmp"
rm -f "$TMP_ARCHIVE"
tar -czpf "$TMP_ARCHIVE" -C "$WORK" "$NAME"
mv "$TMP_ARCHIVE" "$ARCHIVE"
sha256 -q "$ARCHIVE" > "$SHA_FILE"
chmod 600 "$ARCHIVE" "$SHA_FILE"

EXPECTED="$(cat "$SHA_FILE")"
ACTUAL="$(sha256 -q "$ARCHIVE")"
[ "$EXPECTED" = "$ACTUAL" ] || { echo "ERRO: checksum final divergente." >&2; exit 1; }

echo ""
echo "============================================================"
echo " BACKUP AUTO-INSTALAVEL CONCLUIDO"
echo "============================================================"
echo "Arquivo:  $ARCHIVE"
echo "SHA-256: $EXPECTED"
echo "Modo:     $MODE"
echo ""
echo "O pacote contem:"
echo "  ${NAME}/install.sh"
echo "  ${NAME}/payload/"
echo "  ${NAME}/reference/"
echo "  ${NAME}/manifest/"
echo ""
echo "Instalacao:"
echo "  tar -xzf '$ARCHIVE'"
echo "  cd '$NAME'"
echo "  sh install.sh"
echo ""
echo "Validacao do arquivo:"
echo "  test \"\$(sha256 -q '$ARCHIVE')\" = \"\$(cat '$SHA_FILE')\" && echo OK"
