#!/usr/bin/env bash
# ============================================================
# 江苏众拓官网 - 安全加固 + HTTPS 一键脚本
# 作用：安装 certbot，申请 Let's Encrypt 免费证书，
#       自动配置 Nginx 443 + HTTP 跳转 HTTPS + HSTS，
#       全局安全响应头，隐藏 Nginx 版本号，配置证书自动续期。
#
# 前置条件（必须）：
#   1. 域名已在阿里云万网注册
#   2. 域名 A 记录已解析到本机公网 IP
#   3. 已通过 ICP 备案（否则 HTTP-01 验证会被运营商拦截，证书申请失败）
#   4. 以 root 运行
#
# 用法：
#   sudo bash secure.sh
# ============================================================
set -e

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
err(){  echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ "$(id -u)" -eq 0 ] || err "请使用 root 运行：sudo bash secure.sh"

# ---------- 1. 读取域名 ----------
read -p "请输入你的域名（如 alltopjs.com）: " DOMAIN
[ -z "$DOMAIN" ] && err "域名不能为空"
read -p "请输入证书到期提醒邮箱: " CERT_EMAIL
[ -z "$CERT_EMAIL" ] && CERT_EMAIL="6820616@qq.com"

# ---------- 2. 安装 certbot ----------
info "检测系统包管理器 ..."
if command -v apt >/dev/null 2>&1; then PM="apt";
elif command -v dnf >/dev/null 2>&1; then PM="dnf";
elif command -v yum >/dev/null 2>&1; then PM="yum";
else err "不支持的 Linux 发行版"; fi

info "安装 certbot + nginx 插件 ..."
if [ "$PM" = "apt" ]; then
  apt update -y && apt install -y certbot python3-certbot-nginx
else
  "$PM" install -y epel-release 2>/dev/null || true
  "$PM" install -y certbot python3-certbot-nginx
fi

# ---------- 3. 全局安全响应头 ----------
HEADER_FILE="/etc/nginx/conf.d/security-headers.conf"
info "写入全局安全头 -> $HEADER_FILE"
cat > "$HEADER_FILE" <<'EOF'
# 安全响应头（全局生效）
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self';" always;
EOF

if ! grep -q "include /etc/nginx/conf.d/security-headers.conf;" /etc/nginx/nginx.conf; then
  sed -i '/^http {/a\    include /etc/nginx/conf.d/security-headers.conf;' /etc/nginx/nginx.conf
  info "已在 nginx.conf http 块引入安全头"
fi

# ---------- 4. 隐藏 Nginx 版本 ----------
if ! grep -q "server_tokens off;" /etc/nginx/nginx.conf; then
  sed -i '/^http {/a\    server_tokens off;' /etc/nginx/nginx.conf
  info "已关闭 Nginx 版本号显示"
fi

# ---------- 5. 申请证书并自动配置 ----------
info "为 $DOMAIN / www.$DOMAIN 申请证书 ..."
certbot --nginx \
  -d "$DOMAIN" -d "www.$DOMAIN" \
  --non-interactive --agree-tos \
  -m "$CERT_EMAIL" \
  --redirect --hsts \
  || err "证书申请失败。请确认：①域名A记录已指向本机公网IP ②已完成ICP备案 ③80端口安全组已开放"

# ---------- 6. 配置自动续期 ----------
info "配置证书自动续期 ..."
if systemctl list-unit-files 2>/dev/null | grep -q certbot.timer; then
  systemctl enable --now certbot.timer
else
  echo "0 3 * * * root certbot renew --quiet --deploy-hook 'systemctl reload nginx'" > /etc/cron.d/certbot-renew
  info "已写入 cron 每日续期检查"
fi

# ---------- 7. 校验并重载 ----------
nginx -t && systemctl reload nginx
info "✓ 完成！现在可通过 https://$DOMAIN 访问"
warn "ICP 备案未完成前，域名 80/443 可能被运营商拦截；请尽快在 beian.aliyun.com 提交备案。"
