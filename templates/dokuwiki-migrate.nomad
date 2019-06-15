{% from '_lib.hcl' import group_disk, task_logs, continuous_reschedule -%}

job "dokuwiki-migrate" {
  datacenters = ["dc1"]
  type = "batch"
  priority = 45

  group "migrate" {
    ${ group_disk() }

    ${ continuous_reschedule() }

    task "script" {
      ${ task_logs() }

      driver = "docker"
      config = {
        image = "alpine"
        volumes = [
          "${liquid_volumes}/dokuwiki/data:/bitnami",
        ]
        args = ["sh", "/local/migrate.sh"]
        labels {
          liquid_task = "dokuwiki-migrate"
        }
      }
      template {
        destination = "local/migrate.sh"
        data = <<EOF
          set -ex
          doku=/bitnami/dokuwiki
          if ! [ -e $doku/conf/local.php ]; then
            echo "Dokuwiki not ready, aborting in 5s ..."
            sleep 5
            exit 1
          fi
          cp /local/conf-local.php $doku/conf/local.php
          mkdir -p $doku/lib/plugins/liquid
          cp /local/liquid-auth.php $doku/lib/plugins/liquid/auth.php
        EOF
      }
      template {
        destination = "local/liquid-auth.php"
        data = <<-EOF
        <?php
        /**
         * Liquid auth plugin for authproxy
         * Auto-generated by liquid migration script
         * Timestamp: ${config.timestamp}
         */
        define('DOKU_AUTH', dirname(__FILE__));
        define('AUTH_USERFILE', DOKU_CONF.'users.auth.php');
        class auth_plugin_liquid extends DokuWiki_Auth_Plugin {
          function auth_plugin_liquid(){
            global $config_cascade;
            $this->cando['external'] = true;
            $this->success = true;
          }
          function trustExternal($user, $pass, $sticky = false) {
            global $USERINFO;
            if (isset($_SERVER['HTTP_X_FORWARDED_USER'])) {
              $userid = $_SERVER['HTTP_X_FORWARDED_USER'];
              $USERINFO['user'] = $userid;
              $USERINFO['mail'] = $_SERVER['HTTP_X_FORWARDED_USER_EMAIL'];
              $USERINFO['name'] = $_SERVER['HTTP_X_FORWARDED_USER_FULL_NAME'];
              if ($_SERVER['HTTP_X_FORWARDED_USER_ADMIN'] == 'true') {
                $USERINFO['grps'] = array('admin', 'user');
              } else {
                $USERINFO['grps'] = array('user');
              }
              $_SERVER['REMOTE_USER'] = $userid;
              $_SESSION[DOKU_COOKIE]['auth']['user'] = $userid;
              $_SESSION[DOKU_COOKIE]['auth']['info'] = $USERINFO;
              return true;
            }
            return false;
          }
          function logOff() {
            send_redirect('/__auth/logout');
          }
        }
        EOF
      }
      template {
        destination = "local/conf-local.php"
        data = <<-EOF
        <?php
        /**
         * Dokuwiki's Main Configuration File - Local Settings
         * Auto-generated by liquid migration script
         * Timestamp: ${config.timestamp}
         */
        $conf['title'] = 'Liquid DokuWiki';
        $conf['lang'] = 'en';
        $conf['license'] = '0';
        $conf['useacl'] = 1;
        $conf['superuser'] = '@admin';
        $conf['disableactions'] = 'register';
        $conf['authtype'] = 'liquid';
        $conf['defaultgroup'] = 'admin,user';
        $conf['baseurl'] = '${config.liquid_http_protocol}://dokuwiki.${liquid_domain}';
        EOF
      }
      resources {
        memory = 100
        cpu = 200
      }
    }
  }
}
