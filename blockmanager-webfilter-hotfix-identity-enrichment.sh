#!/bin/sh
set -eu
umask 077

FILE="/usr/local/www/blockmanager-webfilter/blockmanager-webfilter-lib.php"
PHP="/usr/local/bin/php"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/blockmanager-webfilter-lib.php.before-identity-${STAMP}"
PATCH="/tmp/bmwf-identity-patch-${STAMP}.php"

[ "$(id -u)" = "0" ] || { echo "ERRO: execute como root." >&2; exit 1; }
[ -f "$FILE" ] || { echo "ERRO: arquivo ausente: $FILE" >&2; exit 1; }
[ -x "$PHP" ] || { echo "ERRO: PHP ausente: $PHP" >&2; exit 1; }

cp -p "$FILE" "$BACKUP"
echo "Backup: $BACKUP"

cat > "$PATCH" <<'PHP'
<?php
$file = '/usr/local/www/blockmanager-webfilter/blockmanager-webfilter-lib.php';
$text = file_get_contents($file);
if ($text === false) { fwrite(STDERR, "ERRO: leitura falhou\n"); exit(2); }

if (strpos($text, 'function bmwf_enrich_event_identity(') !== false) {
    fwrite(STDERR, "ERRO: enriquecimento ja existe; nenhuma alteracao aplicada.\n");
    exit(3);
}

$before = <<<'CODE'
function bmwf_normalize_e2guardian_event(string $line,string $source):?array {
CODE;

$helper = <<<'CODE'
function bmwf_identity_index():array {
    static $cache=null;
    if($cache!==null)return$cache;
    $cache=['by_ip'=>[],'ambiguous'=>[]];
    $snapshot=bmwf_json_read(BMWF_SNAPSHOT_FILE,[]);
    $rows=(array)($snapshot['identities']??$snapshot['items']??$snapshot);
    foreach($rows as$row){
        if(!is_array($row)||array_key_exists('enabled',$row)&&empty($row['enabled']))continue;
        $identity=bmwf_event_value($row['username']??$row['name']??$row['id']??'');
        if($identity==='')continue;
        $ips=[];
        if(!empty($row['ip']))$ips[]=(string)$row['ip'];
        foreach((array)($row['ips']??[])as$ip)$ips[]=(string)$ip;
        foreach(array_unique($ips)as$ip){
            $ip=trim($ip);if(!filter_var($ip,FILTER_VALIDATE_IP))continue;
            if(isset($cache['by_ip'][$ip])&&$cache['by_ip'][$ip]['identity']!==$identity){
                unset($cache['by_ip'][$ip]);$cache['ambiguous'][$ip]=true;continue;
            }
            if(isset($cache['ambiguous'][$ip]))continue;
            $cache['by_ip'][$ip]=['identity'=>$identity,'groups'=>array_values(array_filter(array_map('strval',(array)($row['groups']??[]))))];
        }
    }
    return$cache;
}
function bmwf_enrich_event_identity(array $event):array {
    $ip=trim((string)($event['ip']??''));
    $current=bmwf_event_value($event['identity']??'');
    if($ip===''||($current!==''&&$current!==$ip))return$event;
    $index=bmwf_identity_index();
    if(!empty($index['ambiguous'][$ip])){$event['identity']=$ip;$event['identity_source']='ambiguous';return$event;}
    $match=$index['by_ip'][$ip]??null;
    if(is_array($match)&&!empty($match['identity'])){$event['identity']=(string)$match['identity'];$event['identity_source']='blockmanager_snapshot';}
    else{$event['identity']=$current!==''?$current:$ip;$event['identity_source']='ip_fallback';}
    return$event;
}

CODE;

if (substr_count($text, $before) !== 1) {
    fwrite(STDERR, "ERRO: ponto de insercao nao encontrado exatamente uma vez.\n"); exit(4);
}
$text = str_replace($before, $helper . $before, $text, $n1);

$old1 = '$line=rtrim($line,"\\r\\n");if(trim($line)===\'\')return null;$e2g=bmwf_normalize_e2guardian_event($line,$source);if($e2g!==null)return$e2g;';
$new1 = '$line=rtrim($line,"\\r\\n");if(trim($line)===\'\')return null;$e2g=bmwf_normalize_e2guardian_event($line,$source);if($e2g!==null)return bmwf_enrich_event_identity($e2g);';
if (substr_count($text, $old1) !== 1) {
    fwrite(STDERR, "ERRO: retorno E2Guardian nao encontrado exatamente uma vez.\n"); exit(5);
}
$text = str_replace($old1, $new1, $text, $n2);

$old2 = '    return $event;\n}\nfunction bmwf_collect_log_source';
$new2 = '    return bmwf_enrich_event_identity($event);\n}\nfunction bmwf_collect_log_source';
if (substr_count($text, $old2) !== 1) {
    fwrite(STDERR, "ERRO: retorno generico nao encontrado exatamente uma vez.\n"); exit(6);
}
$text = str_replace($old2, $new2, $text, $n3);

$tmp = $file . '.identity-new';
if (file_put_contents($tmp, $text) === false) { fwrite(STDERR, "ERRO: gravacao temporaria falhou.\n"); exit(7); }
chmod($tmp, 0640);
if (!rename($tmp, $file)) { @unlink($tmp); fwrite(STDERR, "ERRO: promocao atomica falhou.\n"); exit(8); }
echo "OK: helper={$n1}, e2guardian={$n2}, generico={$n3}\n";
PHP

if ! "$PHP" -q "$PATCH"; then
    cp -p "$BACKUP" "$FILE"
    rm -f "$PATCH"
    echo "ERRO: patch falhou; backup restaurado." >&2
    exit 1
fi
rm -f "$PATCH"
chown root:wheel "$FILE"
chmod 0640 "$FILE"

if ! "$PHP" -l "$FILE"; then
    cp -p "$BACKUP" "$FILE"
    echo "ERRO: PHP invalido; backup restaurado." >&2
    exit 1
fi

echo "Hotfix aplicado com sucesso."
echo "Nenhum servico, PF, NAT, anchor ou filter.inc foi alterado."
echo "Rollback: cp -p '$BACKUP' '$FILE'"
