{% from '_lib.hcl' import authproxy_group with context -%}

job "nextcloud" {
  datacenters = ["dc1"]
  type = "service"
  priority = 65

  group "nc" {
    task "nextcloud" {
      constraint {
        attribute = "{% raw %}${meta.liquid_volumes}{% endraw %}"
        operator = "is_set"
      }
      constraint {
        attribute = "{% raw %}${meta.liquid_collections}{% endraw %}"
        operator = "is_set"
      }

      driver = "docker"
      config {
        image = "${config.image('liquid-nextcloud')}"
        volumes = [
          "{% raw %}${meta.liquid_volumes}{% endraw %}/nextcloud/nextcloud:/var/www/html",
          "{% raw %}${meta.liquid_collections}{% endraw %}/uploads/data:/var/www/html/data/uploads/files",
        ]
        args = ["/bin/sh", "-c", "chown -R 33:33 /var/www/html/ && echo chown done && /entrypoint.sh apache2-foreground"]
        port_map {
          http = 80
        }
        labels {
          liquid_task = "nextcloud"
        }
      }
      template {
        data = <<EOF
            {{- range service "nextcloud-pg" }}
              NEXTCLOUD_POSTGRES_HOST = {{.Address}}:{{.Port}}
            {{- end }}
            NEXTCLOUD_HOST = nextcloud.{{ key "liquid_domain" }}
            NEXTCLOUD_ADMIN_USER = admin
            NEXTCLOUD_ADMIN_PASSWORD = admin
            NEXTCLOUD_POSTGRES_DB = nextcloud
            NEXTCLOUD_POSTGRES_USER= postgres
            {{- with secret "liquid/nextcloud/nextcloud.pg" }}
              NEXTCLOUD_POSTGRES_PASSWORD = {{.Data.secret_key}}
            {{- end }}
            {{- with secret "liquid/nextcloud/nextcloud.admin" }}
              OC_PASS= {{.Data.secret_key}}
            {{- end }}
          EOF
        destination = "local/nextcloud.env"
        env = true
      }
      resources {
        network {
          mbits = 1
          port "http" {}
        }
      }
      env {
        NEXTCLOUD_URL = "${config.liquid_http_protocol}://nextcloud.${config.liquid_domain}"
        LIQUID_TITLE = "${config.liquid_title}"
        LIQUID_CORE_URL = "${config.liquid_core_url}"
      }
      template {
        data = <<-EOF
        {{- with secret "liquid/nextcloud/nextcloud.uploads" }}
          UPLOADS_USER_PASSWORD = {{.Data.secret_key | toJSON }}
        {{- end }}
        NEXTCLOUD_ADMIN = "admin"
        {{- with secret "liquid/nextcloud/nextcloud.admin" }}
          NEXTCLOUD_ADMIN_PASSWORD = {{.Data.secret_key | toJSON }}
        {{- end }}
        EOF
        destination = "local/nextcloud-migrate.env"
        env = true
      }
      service {
        name = "nextcloud"
        port = "http"
        check {
          name = "http"
          initial_status = "critical"
          type = "http"
          path = "/status.php"
          interval = "${check_interval}"
          timeout = "${check_timeout}"
          header {
            Host = ["nextcloud.${liquid_domain}"]
          }
        }
      }
    }
  }

  group "db" {
    task "maria" {
      constraint {
        attribute = "{% raw %}${meta.liquid_volumes}{% endraw %}"
        operator = "is_set"
      }

      driver = "docker"
      config {
        image = "postgres:9.6"
        volumes = [
          "{% raw %}${meta.liquid_volumes}{% endraw %}/nextcloud/mysql:/var/lib/mysql",
        ]
        labels {
          liquid_task = "nextcloud-pg"
        }
        port_map {
          pg = 5432
        }
      }
      template {
        data = <<-EOF
        MYSQL_RANDOM_ROOT_PASSWORD = "yes"
        MYSQL_DATABASE = "nextcloud"
        MYSQL_USER = "nextcloud"
        {{- with secret "liquid/nextcloud/nextcloud.maria" }}
          MYSQL_PASSWORD = {{.Data.secret_key | toJSON }}
        {{- end }}
        EOF
        destination = "local/pg.env"
        env = true
      }
      resources {
        network {
          mbits = 1
          port "maria" {
            static = 8767
          }
        }
      }
      service {
        name = "nextcloud-maria"
        port = "maria"
        check {
          name = "tcp"
          initial_status = "critical"
          type = "tcp"
          interval = "${check_interval}"
          timeout = "${check_timeout}"
        }
      }
    }
  }

  ${- authproxy_group(
      'nextcloud',
      host='nextcloud.' + liquid_domain,
      upstream='nextcloud',
  )}

}
