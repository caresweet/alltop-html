#!/bin/bash
# ============================================================
# 江苏众拓公司官网 - 阿里云ECS一键部署脚本
# 在阿里云工作台或SSH终端以 root 执行：bash deploy.sh
# ============================================================
set -e

echo "=========================================="
echo "  江苏众拓公司官网 部署脚本"
echo "=========================================="

# 1. 检测系统
echo ""
echo "[1/6] 检测操作系统..."
if command -v dnf &>/dev/null; then
    PM=dnf
elif command -v yum &>/dev/null; then
    PM=yum
elif command -v apt &>/dev/null; then
    PM=apt
else
    echo "✗ 不支持的系统，请手动部署"; exit 1
fi
echo "  包管理器: $PM"

# 2. 安装 nginx git curl unzip
echo ""
echo "[2/6] 安装 Nginx / Git / curl / unzip..."
if [ "$PM" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nginx git curl unzip
else
    $PM install -y nginx git curl unzip
fi
echo "  ✓ 安装完成"

# 3. 获取网站代码
echo ""
echo "[3/6] 获取网站代码..."
mkdir -p /var/www
rm -rf /var/www/alltop
if git clone --depth 1 https://github.com/caresweet/alltop-html.git /var/www/alltop 2>/dev/null; then
    echo "  ✓ 从 GitHub 克隆成功"
else
    echo "  ! GitHub 克隆较慢或失败，尝试下载 ZIP..."
    if curl -fL --connect-timeout 30 -o /tmp/alltop.zip https://github.com/caresweet/alltop-html/archive/refs/heads/main.zip 2>/dev/null; then
        cd /tmp && unzip -oq alltop.zip
        mkdir -p /var/www/alltop
        cp -r alltop-html-main/* /var/www/alltop/
        cp -r alltop-html-main/.[!.]* /var/www/alltop/ 2>/dev/null || true
        rm -rf /tmp/alltop.zip /tmp/alltop-html-main
        echo "  ✓ 从 ZIP 下载成功"
    else
        echo "  ✗ 代码获取失败：服务器无法访问 github.com"
        echo "  解决：1) 重试  2) 把本地 zhongtuo-website 目录用 scp 上传到 /var/www/alltop"
        exit 1
    fi
fi

# 4. 配置 Nginx
echo ""
echo "[4/6] 配置 Nginx..."
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

cat > /etc/nginx/conf.d/alltop.conf << 'NGINXEOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/alltop;
    index index.html;
    charset utf-8;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2?|ttf)$ {
        expires 7d;
        add_header Cache-Control "public, no-transform";
    }

    error_page 404 /index.html;
}
NGINXEOF

echo "  ✓ 配置已写入 /etc/nginx/conf.d/alltop.conf"

# 5. 测试并启动 Nginx
echo ""
echo "[5/6] 启动 Nginx..."
nginx -t
systemctl restart nginx
systemctl enable nginx
echo "  ✓ Nginx 已启动并设为开机自启"

# 6. 检查系统防火墙
echo ""
echo "[6/6] 检查系统防火墙..."
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-service=http 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    echo "  ✓ firewalld 已放行 80 端口"
elif command -v ufw &>/dev/null; then
    ufw allow 80/tcp 2>/dev/null || true
    echo "  ✓ ufw 已放行 80 端口"
else
    echo "  - 未检测到系统防火墙（阿里云安全组仍需单独配置）"
fi

echo ""
echo "=========================================="
echo "  ✓ 部署完成！"
echo "=========================================="
echo ""
echo "本机验证："
curl -s -o /dev/null -w "  本机 HTTP 状态: %{http_code}\n" http://127.0.0.1/
echo ""
echo "⚠  重要：请到阿里云控制台放行安全组 80 端口（入方向 TCP）"
echo "   ECS控制台 → 实例 → 安全组 → 配置规则 → 入方向 → 添加 80/TCP"
echo ""
echo "访问地址：http://<你的服务器公网IP>"
echo ""
echo "更新网站：cd /var/www/alltop && git pull"
