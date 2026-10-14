#!/bin/sh
set -eu
umask 077
PHP=/usr/local/bin/php
BM=/usr/local/www/block_manager.php
SVC=/usr/local/sbin/blockmanager-webfilter-service.php
STAMP=$(date +%Y%m%d-%H%M%S)
BAK=/root/blockmanager-webfilter-master-sync-$STAMP
PATCH=/tmp/bmwf-master-sync-$STAMP.php

[ "$(id -u)" = 0 ] || { echo "ERRO: execute como root." >&2; exit 1; }
[ -x "$PHP" ] || { echo "ERRO: PHP CLI ausente." >&2; exit 1; }
[ -f "$BM" ] && [ -f "$SVC" ] || { echo "ERRO: arquivos alvo ausentes." >&2; exit 1; }
mkdir -p "$BAK"
cp -p "$BM" "$BAK/block_manager.php"
cp -p "$SVC" "$BAK/blockmanager-webfilter-service.php"
echo "Backup: $BAK"

cat > "$PATCH" <<'PHP'
<?php
$bm='/usr/local/www/block_manager.php';
$svc='/usr/local/sbin/blockmanager-webfilter-service.php';

function patch_once(string $file,string $old,string $new,string $label):void{
    $s=file_get_contents($file);if($s===false){fwrite(STDERR,"ERRO leitura $label\n");exit(10);}
    if(strpos($s,$new)!==false){fwrite(STDERR,"ERRO $label ja aplicado\n");exit(11);}
    $n=substr_count($s,$old);if($n!==1){fwrite(STDERR,"ERRO $label: esperado 1 ponto, encontrado $n\n");exit(12);}
    $s=str_replace($old,$new,$s,$count);$tmp=$file.'.master-sync-new';
    if(file_put_contents($tmp,$s)===false||!rename($tmp,$file)){@unlink($tmp);fwrite(STDERR,"ERRO gravacao $label\n");exit(13);}
    echo "OK $label=$count\n";
}

$serviceMarker=<<<'CODE'
function bmwf_service_main(array $argv):int{
CODE;
$serviceInsert=<<<'CODE'
function bmwf_service_ipgroups_path():string{return BMWF_CONFIG_DIR.'/generated/lists/authplugins/ipgroups';}
function bmwf_service_ipgroups_map(string $path):array{$out=[];if(!is_file($path))return$out;foreach(preg_split('/\R/',(string)file_get_contents($path))as$line){if(preg_match('/^\s*((?:\d{1,3}\.){3}\d{1,3})\s*=\s*(filter\d+)\s*$/',$line,$m))$out[$m[1]]=$m[2];}ksort($out,SORT_STRING);return$out;}
function bmwf_service_changed_ips(array $before,array $after):array{$ips=[];foreach(array_unique(array_merge(array_keys($before),array_keys($after)))as$ip)if(($before[$ip]??null)!==($after[$ip]??null))$ips[]=$ip;sort($ips,SORT_STRING);return$ips;}
function bmwf_service_wait_listeners(array $settings,int $seconds=12):array{$need=[(int)($settings['activation']['http_port']??8080)];if((string)($settings['activation']['https_profile']??'off')!=='off')$need[]=(int)($settings['activation']['https_port']??8443);$last='';for($i=0;$i<$seconds;$i++){if(is_executable('/usr/bin/sockstat')){$r=bmwf_exec(['/usr/bin/sockstat','-4','-6','-l']);$last=(string)($r['output']??'');$ok=true;foreach($need as$port)if(!preg_match('/[:.]'.preg_quote((string)$port,'/').'(?:\s|$)/',$last)){$ok=false;break;}if($ok)return['ok'=>true,'exit_code'=>0,'output'=>'Listeners ativos: '.implode(', ',$need)];}sleep(1);}return['ok'=>false,'exit_code'=>1,'output'=>'Listeners nao confirmados: '.implode(', ',$need).' '.$last];}
function bmwf_service_sync_master(array $settings):array{
    $enabled=!empty($settings['enabled']);$wasActive=is_file(BMWF_ACTIVATION_FILE);$before=bmwf_service_ipgroups_map(bmwf_service_ipgroups_path());
    $catalog=bmwf_service_cli('/usr/local/sbin/blockmanager-identity-catalog-worker.php');if(!$catalog['ok'])return bmwf_service_fail_open($settings,'Falha ao atualizar catalogo mestre: '.$catalog['output']);
    $sync=bmwf_service_cli('/usr/local/sbin/blockmanager-webfilter-worker.php',['--sync-identities']);if(!$sync['ok'])return bmwf_service_fail_open($settings,'Falha ao sincronizar identidades: '.$sync['output']);
    $compile=bmwf_service_cli('/usr/local/sbin/blockmanager-webfilter-worker.php',['--compile']);if(!$compile['ok'])return bmwf_service_fail_open($settings,'Falha ao compilar politica: '.$compile['output']);
    $afterCompile=bmwf_service_ipgroups_map(bmwf_service_ipgroups_path());$changed=bmwf_service_changed_ips($before,$afterCompile);
    if(!$enabled)return['ok'=>true,'exit_code'=>0,'output'=>'Cadastro sincronizado e politica compilada; Web Filter desabilitado, runtime nao alterado. IPs alterados: '.implode(',',$changed)];
    $generate=bmwf_service_cli('/usr/local/sbin/blockmanager-webfilter-engine.php',['generate']);if(!$generate['ok'])return bmwf_service_fail_open($settings,'Falha ao gerar configuracao: '.$generate['output']);
    $test=bmwf_backend_action('test',$settings);if(!$test['ok'])return bmwf_service_fail_open($settings,'E2Guardian rejeitou configuracao: '.$test['output']);
    $pfTest=bmwf_service_cli('/usr/local/sbin/blockmanager-webfilter-traffic.php',['test']);if(!$pfTest['ok'])return bmwf_service_fail_open($settings,'PF rejeitou configuracao: '.$pfTest['output']);
    $status=bmwf_backend_action('status',$settings);$running=!empty($status['ok']);
    if($wasActive){$remove=bmwf_service_cli('/usr/local/sbin/blockmanager-webfilter-traffic.php',['remove']);if(!$remove['ok'])return bmwf_service_fail_open($settings,'Falha ao remover redirecionamento antes do restart: '.$remove['output']);}
    if($running){$stop=bmwf_backend_action('stop',$settings);if(!$stop['ok'])return bmwf_service_fail_open($settings,'Falha ao parar E2Guardian: '.$stop['output']);}
    if($running||$wasActive){$start=bmwf_backend_action('start',$settings);if(!$start['ok'])return bmwf_service_fail_open($settings,'Falha ao iniciar E2Guardian: '.$start['output']);$listeners=bmwf_service_wait_listeners($settings);if(!$listeners['ok'])return bmwf_service_fail_open($settings,$listeners['output']);}
    if($wasActive){$traffic=bmwf_service_cli('/usr/local/sbin/blockmanager-webfilter-traffic.php',['apply']);if(!$traffic['ok'])return bmwf_service_fail_open($settings,'Falha ao reaplicar producao: '.$traffic['output']);}
    if(is_executable('/sbin/pfctl'))foreach($changed as$ip)bmwf_exec(['/sbin/pfctl','-k',$ip]);
    if($wasActive)bmwf_atomic_json(BMWF_ACTIVATION_FILE,['activated_at'=>date(DATE_ATOM),'mode'=>$settings['mode'],'scope'=>'production-all-compiled-networks','interfaces'=>$settings['activation']['interfaces'],'https_profile'=>$settings['activation']['https_profile'],'fail_open'=>(bool)$settings['activation']['fail_open'],'last_apply'=>'master-data-sync']);
    return['ok'=>true,'exit_code'=>0,'output'=>'Dados mestres sincronizados, politica compilada'.(($running||$wasActive)?', E2Guardian reiniciado':'').($wasActive?' e producao reaplicada':'').'. Estados limpos para: '.($changed?implode(', ',$changed):'nenhum IP alterado').'.'];
}
function bmwf_service_main(array $argv):int{
CODE;
patch_once($svc,$serviceMarker,$serviceInsert,'service-helper');

$branchOld=<<<'CODE'
      if($action==='apply')$result=bmwf_service_apply($settings);
CODE;
$branchNew=<<<'CODE'
      if($action==='sync-master')$result=bmwf_service_sync_master($settings);
      elseif($action==='apply')$result=bmwf_service_apply($settings);
CODE;
patch_once($svc,$branchOld,$branchNew,'service-action');

$bmOld=<<<'CODE'
 $message=$result['msg'];$message_type=$result['ok']?'success':'error';
CODE;
$bmNew=<<<'CODE'
 if(!empty($result['ok'])&&in_array($action,['save_user','delete_user','sync_mac_bindings','save_network','delete_network','add_group','delete_group','save_group_connectors'],true)){
  $bmwfMasterSync=bmwf_run_cli('/usr/local/sbin/blockmanager-webfilter-service.php',['sync-master']);
  if(!empty($bmwfMasterSync['ok']))$result['msg'].=' Web Filter sincronizado e runtime atualizado automaticamente.';
  else{$result['msg'].=' Cadastro salvo, mas a sincronizacao automatica do Web Filter falhou: '.trim((string)($bmwfMasterSync['output']??'erro desconhecido'));$result['webfilter_sync_ok']=false;}
 }
 $message=$result['msg'];$message_type=$result['ok']?'success':'error';
CODE;
patch_once($bm,$bmOld,$bmNew,'block-manager-hook');
PHP

if ! "$PHP" -q "$PATCH"; then
  cp -p "$BAK/block_manager.php" "$BM"
  cp -p "$BAK/blockmanager-webfilter-service.php" "$SVC"
  rm -f "$PATCH"
  echo "ERRO: patch falhou; arquivos restaurados." >&2
  exit 1
fi
rm -f "$PATCH"
chown root:wheel "$BM" "$SVC"
chmod 0644 "$BM"
chmod 0755 "$SVC"

for f in "$BM" "$SVC"; do
  if ! "$PHP" -l "$f"; then
    cp -p "$BAK/block_manager.php" "$BM"
    cp -p "$BAK/blockmanager-webfilter-service.php" "$SVC"
    echo "ERRO: lint falhou; arquivos restaurados." >&2
    exit 1
  fi
done

echo "Hotfix aplicado com sucesso."
echo "Integracao: Usuarios/Identidades -> sync-master -> catalogo -> snapshot -> compilacao -> restart controlado -> PF."
echo "Rollback: cp -p '$BAK/block_manager.php' '$BM' && cp -p '$BAK/blockmanager-webfilter-service.php' '$SVC'"
