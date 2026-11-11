E2GUARDIAN SSL ENGINE PARA PFSENSE CE 2.9
===========================================

Build do motor E2Guardian com suporte a SSL, preparada especificamente para o pfSense CE 2.9.0 baseado no FreeBSD 16-CURRENT.

IMPORTANTE
----------
Este pacote contém somente o motor E2Guardian com suporte a SSL.

Não inclui:
- WebGUI;
- interface ou integração completa do Block Manager;
- políticas prontas de navegação;
- listas de categorias;
- criação automática de CA ou certificados;
- gerenciamento de usuários, LDAP ou Active Directory;
- regras PF, NAT ou RDR;
- relatórios e Analytics;
- scripts de instalação integral do Web Filter;
- Squid ou SquidGuard.

O suporte SSL presente no binário não ativa automaticamente a inspeção HTTPS. A operação completa depende de configuração externa, certificados, listeners, políticas e redirecionamento de tráfego.

AMBIENTE DE COMPILAÇÃO E HOMOLOGAÇÃO
-------------------------------------

Sistema: pfSense CE 2.9.0-RELEASE
Sistema-base: FreeBSD 16.0-CURRENT
Arquitetura: amd64
Kernel ABI: 1600018
Package ABI: FreeBSD:16:amd64
OpenSSL: 3.5.7
PHP do ambiente: 8.5.7
E2Guardian: 5.5.9r

Comandos usados para identificar o ambiente:

cat /etc/version
freebsd-version -ku
uname -K
uname -m
pkg config ABI
openssl version
php -v

Saída de referência:

pfSense:       2.9.0-RELEASE
FreeBSD:       16.0-CURRENT
Kernel ABI:    1600018
Arquitetura:   amd64
Package ABI:   FreeBSD:16:amd64
OpenSSL:       3.5.7
PHP:           8.5.7

COMPATIBILIDADE
---------------

Esta build deve ser usada somente em sistemas compatíveis com:

FreeBSD:16:amd64

Antes da instalação, execute:

pkg config ABI

Resultado esperado:

FreeBSD:16:amd64

Compatível com:
- pfSense CE 2.9.0;
- FreeBSD 16-CURRENT correspondente à build;
- arquitetura amd64;
- OpenSSL compatível com a versão usada na compilação.

Não compatível com:
- pfSense CE 2.7.2;
- FreeBSD 14;
- ABI FreeBSD:14:amd64;
- arm64 ou aarch64;
- outras versões do pfSense sem validação;
- versões incompatíveis do OpenSSL.

O pfSense CE 2.7.2 utiliza FreeBSD 14 e ABI FreeBSD:14:amd64. Esse ambiente exige outra compilação. Não force a instalação desta build com pkg add -f.

ESCOPO DO MOTOR SSL
-------------------

Esta versão fornece o motor necessário para filtragem HTTP e inspeção HTTPS do E2Guardian.

Incluído:
- executável do E2Guardian;
- suporte a SSL/TLS;
- suporte à inspeção HTTPS quando configurado com uma CA;
- suporte aos arquivos de configuração nativos do E2Guardian;
- suporte às listas, grupos e plugins disponibilizados pela build;
- execução nativa em amd64;
- compatibilidade com FreeBSD:16:amd64.

Para ativar a inspeção HTTPS ainda são necessários:
1. CA válida;
2. certificado e chave privada;
3. configuração dos certificados no E2Guardian;
4. arquivos e2guardian.conf e e2guardianfN.conf;
5. listeners HTTP e HTTPS;
6. regras PF/RDR;
7. instalação da CA nos dispositivos clientes;
8. política de exceções SSL;
9. validação do runtime.

No Block Manager, certificados e autoridades certificadoras gerados pelo instalador devem usar a identidade "Block Manager". Não utilizar "SystemWay" na identidade visível dos certificados.

VALIDAÇÃO DO BINÁRIO
--------------------

Após a instalação:

/usr/local/sbin/e2guardian -v

Verifique as dependências:

ldd /usr/local/sbin/e2guardian

Nenhuma biblioteca deve aparecer como "not found".

Confira o executável:

file /usr/local/sbin/e2guardian

Confira o pacote:

pkg info e2guardian
pkg check -d e2guardian
pkg check -s e2guardian

VALIDAÇÃO DO SERVIÇO
--------------------

service e2guardian status
ps auxww | grep '[e]2guardian'
sockstat -4 -6 -l | grep e2guardian

Em uma integração típica do Block Manager:

127.0.0.1:8080  HTTP
127.0.0.1:8443  HTTPS transparente

Essas portas são referências da arquitetura integrada e não são configuradas automaticamente pelo motor publicado neste repositório.

TESTE DE CONFIGURAÇÃO
---------------------

Antes de iniciar ou reiniciar o serviço:

/usr/local/sbin/e2guardian -Q
echo "exit=$?"

Resultado esperado:

exit=0

Consulte as opções disponíveis:

/usr/local/sbin/e2guardian --help

Não reinicie o serviço em produção se o teste retornar erro.

OPENSSL E BIBLIOTECAS
---------------------

Esta build foi gerada para OpenSSL 3.5.7.

Valide as ligações do binário:

ldd /usr/local/sbin/e2guardian | grep -E 'ssl|crypto'

Não tente resolver incompatibilidades criando links simbólicos entre versões diferentes de libssl ou libcrypto, por exemplo:

ln -s libssl.so.X libssl.so.Y
ln -s libcrypto.so.X libcrypto.so.Y

Links simbólicos não tornam ABIs incompatíveis em ABIs compatíveis.

INSTALAÇÃO
----------

Valide o hash publicado junto à release:

sha256 e2guardian-*.pkg

Inspecione o pacote:

pkg info -F ./e2guardian-*.pkg

Confirme a arquitetura:

FreeBSD:16:amd64

Instale somente depois dessa validação:

pkg add ./e2guardian-*.pkg

Depois valide:

pkg info e2guardian
/usr/local/sbin/e2guardian -v
ldd /usr/local/sbin/e2guardian

INFORMAÇÕES DE COMPILAÇÃO
-------------------------

Preserve junto à release:

cat /etc/version
freebsd-version -ku
uname -a
uname -K
uname -m
pkg config ABI
openssl version -a
cc --version
c++ --version

Também devem ser publicados, quando disponíveis:
- versão ou commit do código-fonte;
- origem do código-fonte;
- data da compilação;
- comando configure utilizado;
- opções habilitadas e desabilitadas;
- compilador e versão;
- lista de dependências;
- SHA-256 do pacote;
- SHA-256 do executável;
- saída de ldd;
- manifesto do pacote.

ATENÇÃO SOBRE O RECIPE DE BUILD
-------------------------------

O recipe integral de compilação não deve ser preenchido por estimativa. Se config.log e o histórico da compilação ainda estiverem disponíveis, recupere o comando real com:

grep -nE 'configure|Configured with|SSL|OpenSSL|enable-|disable-|prefix' config.log

history | grep -E 'configure|gmake|make|cmake|e2guardian'

Registre somente as opções realmente utilizadas:

./configure \
  [OPÇÕES REAIS UTILIZADAS NA COMPILAÇÃO]

Não publique flags presumidas como se fossem o comando original.

LIMITAÇÕES
----------

- Este repositório não entrega uma solução Web Filter completa.
- O motor depende de configuração externa.
- A inspeção SSL exige CA instalada e confiável nos clientes.
- Aplicações com certificate pinning podem falhar durante a inspeção.
- QUIC/HTTP3 precisa ser tratado separadamente quando a política exige inspeção HTTPS.
- Atualizações do pfSense, FreeBSD ou OpenSSL podem exigir recompilação.
- Esta build não deve ser aplicada a outro ABI usando pkg add -f.

SEGURANÇA
---------

A inspeção HTTPS permite o processamento de conteúdo descriptografado. A implantação deve considerar:

- escopo da inspeção;
- exceções para serviços bancários, saúde e outros serviços sensíveis;
- proteção da chave privada da CA;
- permissões restritas nos arquivos;
- retenção de logs;
- legislação e políticas de privacidade;
- controle administrativo do firewall.

Nunca publique a chave privada da CA no repositório.

LICENÇA
-------

O código-fonte e os binários devem preservar os avisos e a licença do projeto E2Guardian original. Dependências de terceiros podem possuir licenças próprias.

AVISO
-----

Este projeto não é uma distribuição oficial do pfSense nem da Netgate.

pfSense é marca de seus respectivos proprietários. E2Guardian e os demais componentes mantêm suas próprias licenças e marcas.

DESCRIÇÃO CURTA PARA O GITHUB
-----------------------------

E2Guardian 5.5.9r SSL engine build for pfSense CE 2.9.0 / FreeBSD 16 amd64. Engine only, without WebGUI, policies or Block Manager integration.

NOME SUGERIDO PARA A RELEASE
----------------------------

E2Guardian 5.5.9r SSL Engine - pfSense CE 2.9.0 / FreeBSD 16 amd64

TEXTO CURTO PARA A RELEASE
--------------------------

Build do motor E2Guardian 5.5.9r com suporte SSL para pfSense CE 2.9.0, FreeBSD 16-CURRENT e arquitetura amd64.

Compatibilidade:
- pfSense CE 2.9.0-RELEASE
- FreeBSD 16.0-CURRENT
- ABI FreeBSD:16:amd64
- Kernel ABI 1600018
- OpenSSL 3.5.7

Esta release contém somente o motor E2Guardian com suporte SSL.
Não inclui WebGUI, políticas, listas, CA, certificados, regras PF/RDR, relatórios ou integração completa com o Block Manager.

Não instalar no pfSense 2.7.2 ou FreeBSD 14.
