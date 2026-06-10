#!/usr/bin/env bash
#
# precheck.sh — QuickCheck QA 接单前链接预检脚本
#
# 用法:
#   ./precheck.sh https://client-website.co.nz
#
# 可选环境变量(没有也能用,会降级为给出人工检查链接):
#   VT_API_KEY   VirusTotal 免费 API key   https://www.virustotal.com/gui/my-apikey
#   GSB_API_KEY  Google Safe Browsing key  https://developers.google.com/safe-browsing
#
# 退出码: 0 = 全部通过 / 1 = 有 WARN / 2 = 有 FAIL(建议拒单) / 3 = 用法错误
#
set -u

# ---------- 颜色 ----------
if [ -t 1 ]; then
  RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; DIM=$'\033[2m'; BLD=$'\033[1m'; RST=$'\033[0m'
else
  RED=''; GRN=''; YLW=''; DIM=''; BLD=''; RST=''
fi

FAILS=0; WARNS=0
pass() { printf '%sPASS%s  %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '%sWARN%s  %s\n' "$YLW" "$RST" "$1"; WARNS=$((WARNS+1)); }
fail() { printf '%sFAIL%s  %s\n' "$RED" "$RST" "$1"; FAILS=$((FAILS+1)); }
info() { printf '%s      %s%s\n' "$DIM" "$1" "$RST"; }
head_() { printf '\n%s── %s ──%s\n' "$BLD" "$1" "$RST"; }

# ---------- 0. 参数 ----------
URL="${1:-}"
if [ -z "$URL" ]; then
  echo "用法: $0 <https://client-website.co.nz>" >&2
  exit 3
fi
case "$URL" in
  http://*|https://*) : ;;
  *) echo "请提供带 http(s):// 的完整网址" >&2; exit 3 ;;
esac

# 提取域名(去协议、路径、端口、用户信息)
DOMAIN=$(printf '%s' "$URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#^[^@]*@##; s#:[0-9]+$##' | tr 'A-Z' 'a-z')

printf '%sQuickCheck 链接预检%s  %s\n' "$BLD" "$RST" "$URL"
printf '%s域名: %s · %s%s\n' "$DIM" "$DOMAIN" "$(date '+%Y-%m-%d %H:%M')" "$RST"

# ---------- 1. 红线特征 ----------
head_ "1/5 红线特征"

# 裸 IP?
if printf '%s' "$DOMAIN" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  fail "网址是裸 IP 地址 — 红线,正常生意网站不会这样,建议直接拒单"
else
  pass "不是裸 IP 地址"
fi

# 缩短链接?
SHORTENERS='bit.ly|tinyurl.com|t.co|goo.gl|is.gd|buff.ly|rebrand.ly|cutt.ly|shorturl.at|rb.gy|tiny.cc|ow.ly|s.id'
if printf '%s' "$DOMAIN" | grep -Eq "^($SHORTENERS)$"; then
  fail "这是缩短链接($DOMAIN)— 红线,要求客户提供原始网址"
else
  pass "不是已知的缩短链接服务"
fi

# 非 HTTPS?
case "$URL" in
  https://*) pass "使用 HTTPS" ;;
  *)         warn "网站使用 HTTP 明文协议 — 2026 年还没上 HTTPS 的站要多留个心眼(这本身也是一条可写进报告的发现)" ;;
esac

# 可疑的超长域名 / punycode
if [ "${#DOMAIN}" -gt 50 ]; then
  warn "域名异常长(${#DOMAIN} 字符)— 人工确认一下"
fi
if printf '%s' "$DOMAIN" | grep -q 'xn--'; then
  warn "域名含 punycode(xn--)— 可能是同形字仿冒域名,人工核对显示字符"
fi

# ---------- 2. whois 域名年龄 ----------
head_ "2/5 域名背景 (whois)"
if command -v whois >/dev/null 2>&1; then
  WHOIS_OUT=$(whois "$DOMAIN" 2>/dev/null)
  # 常见注册日期字段: Creation Date / created / registered / Registered on
  CREATED=$(printf '%s\n' "$WHOIS_OUT" \
    | grep -iE '^( *)(creation date|created|registered( on)?|domain_dateregistered|registration date)' \
    | head -1 | sed -E 's/^[^:]+:\s*//')
  if [ -n "$CREATED" ]; then
    info "注册时间: $CREATED"
    # 提取年份做粗略年龄判断
    YEAR=$(printf '%s' "$CREATED" | grep -oE '(19|20)[0-9]{2}' | head -1)
    NOW_YEAR=$(date +%Y)
    if [ -n "$YEAR" ]; then
      AGE=$((NOW_YEAR - YEAR))
      if [ "$AGE" -lt 1 ]; then
        warn "域名是今年/近一年内注册的 — 新域名+「老牌生意」的说法对不上就要警惕"
      else
        pass "域名已存在约 ${AGE} 年"
      fi
    else
      warn "无法解析注册年份,人工看一眼上面的注册时间"
    fi
  else
    warn "whois 未返回注册日期(部分 .nz 域名有隐私设置)— 可到 dnc.org.nz 人工查询"
  fi
else
  warn "本机没有 whois 命令(macOS 自带;Linux: sudo apt install whois)— 跳过,可到 dnc.org.nz 人工查询"
fi

# ---------- 3. TLS 证书 ----------
head_ "3/5 TLS 证书"
if command -v openssl >/dev/null 2>&1 && [ "${URL%%:*}" = "https" ]; then
  CERT=$(printf '' | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
         | openssl x509 -noout -issuer -enddate 2>/dev/null)
  if [ -n "$CERT" ]; then
    ISSUER=$(printf '%s\n' "$CERT" | grep -i '^issuer'  | sed 's/^issuer=//I')
    ENDDATE=$(printf '%s\n' "$CERT" | grep -i 'notAfter' | sed 's/notAfter=//I')
    info "签发者: ${ISSUER:-未知}"
    info "到期日: ${ENDDATE:-未知}"
    # 证书是否已过期
    if printf '' | openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null \
       | openssl x509 -noout -checkend 0 >/dev/null 2>&1; then
      pass "证书有效未过期"
    else
      fail "证书已过期或无法验证 — 不要继续访问"
    fi
  else
    warn "无法取得证书信息(站点不可达或拦截了探测)— 人工确认浏览器锁图标"
  fi
else
  [ "${URL%%:*}" = "https" ] && warn "本机没有 openssl — 跳过证书检查" || info "HTTP 站点,无证书可查"
fi

# ---------- 4. HTTP 可达性与重定向 ----------
head_ "4/5 HTTP 可达性"
if command -v curl >/dev/null 2>&1; then
  # 只发 HEAD,不下载内容;限时 15 秒;跟随最多 5 次重定向
  RESP=$(curl -sIL --max-time 15 --max-redirs 5 -o /dev/null \
         -w 'code=%{http_code} final=%{url_effective} redirects=%{num_redirects}' \
         "$URL" 2>/dev/null)
  if [ -n "$RESP" ]; then
    CODE=$(printf '%s' "$RESP" | sed -E 's/.*code=([0-9]+).*/\1/')
    FINAL=$(printf '%s' "$RESP" | sed -E 's/.*final=([^ ]+).*/\1/')
    NREDIR=$(printf '%s' "$RESP" | sed -E 's/.*redirects=([0-9]+).*/\1/')
    info "状态码: $CODE · 重定向次数: $NREDIR"
    info "最终地址: $FINAL"
    FINAL_DOMAIN=$(printf '%s' "$FINAL" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#:[0-9]+$##' | tr 'A-Z' 'a-z')
    if [ "$CODE" -ge 200 ] && [ "$CODE" -lt 400 ]; then
      pass "站点可达"
    else
      warn "HTTP 状态码 $CODE — 站点可能有问题(也可能拦截了 curl,人工确认)"
    fi
    if [ "$FINAL_DOMAIN" != "$DOMAIN" ] && [ -n "$FINAL_DOMAIN" ]; then
      warn "最终落地域名($FINAL_DOMAIN)和客户给的域名不同 — 跳转去了别的站,人工确认是否合理(如 www 跳转属正常)"
    else
      pass "没有跳转到其它域名"
    fi
  else
    warn "站点无响应或超时 — 人工确认"
  fi
else
  warn "本机没有 curl — 跳过"
fi

# ---------- 5. 信誉库查询 ----------
head_ "5/5 信誉库 (VirusTotal / Google Safe Browsing)"

# VirusTotal: API v3 的 URL id 是 base64url(原始网址) 去掉 = 填充
if [ -n "${VT_API_KEY:-}" ]; then
  VT_ID=$(printf '%s' "$URL" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')
  VT_JSON=$(curl -s --max-time 20 -H "x-apikey: $VT_API_KEY" \
            "https://www.virustotal.com/api/v3/urls/$VT_ID" 2>/dev/null)
  MAL=$(printf '%s' "$VT_JSON" | grep -o '"malicious"[: ]*[0-9]*' | head -1 | grep -o '[0-9]*$')
  SUS=$(printf '%s' "$VT_JSON" | grep -o '"suspicious"[: ]*[0-9]*' | head -1 | grep -o '[0-9]*$')
  if [ -n "$MAL" ]; then
    info "VirusTotal: malicious=$MAL suspicious=${SUS:-0}"
    if [ "$MAL" -ge 3 ]; then
      fail "VirusTotal 有 $MAL 个引擎报恶意 — 拒单"
    elif [ "$MAL" -ge 1 ] || [ "${SUS:-0}" -ge 2 ]; then
      warn "VirusTotal 有少量检出 — 打开报告人工判断: https://www.virustotal.com/gui/url/$VT_ID"
    else
      pass "VirusTotal 无恶意检出"
    fi
  else
    warn "VirusTotal 无该网址的现成报告(或 API 出错)— 到网页版提交扫描: https://www.virustotal.com/gui/home/url"
  fi
else
  warn "未设置 VT_API_KEY — 请人工扫描: https://www.virustotal.com/gui/home/url"
  info "免费申请 key: https://www.virustotal.com/gui/my-apikey,然后 export VT_API_KEY=..."
fi

# Google Safe Browsing
if [ -n "${GSB_API_KEY:-}" ]; then
  GSB_JSON=$(curl -s --max-time 20 -X POST \
    "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=$GSB_API_KEY" \
    -H 'Content-Type: application/json' \
    -d "{\"client\":{\"clientId\":\"quickcheck-qa\",\"clientVersion\":\"1.0\"},
         \"threatInfo\":{
           \"threatTypes\":[\"MALWARE\",\"SOCIAL_ENGINEERING\",\"UNWANTED_SOFTWARE\"],
           \"platformTypes\":[\"ANY_PLATFORM\"],
           \"threatEntryTypes\":[\"URL\"],
           \"threatEntries\":[{\"url\":\"$URL\"}]}}" 2>/dev/null)
  if printf '%s' "$GSB_JSON" | grep -q '"matches"'; then
    fail "Google Safe Browsing 命中威胁列表 — 拒单"
  elif [ -n "$GSB_JSON" ] && ! printf '%s' "$GSB_JSON" | grep -q '"error"'; then
    pass "Google Safe Browsing 无命中"
  else
    warn "Safe Browsing API 出错 — 人工查询: https://transparencyreport.google.com/safe-browsing/search?url=$DOMAIN"
  fi
else
  warn "未设置 GSB_API_KEY — 请人工查询: https://transparencyreport.google.com/safe-browsing/search?url=$DOMAIN"
fi

# ---------- 总结 ----------
printf '\n%s══ 预检结果 ══%s\n' "$BLD" "$RST"
if [ "$FAILS" -gt 0 ]; then
  printf '%s✗ %d 项 FAIL,%d 项 WARN — 建议拒单,或要求客户澄清后重新预检%s\n' "$RED" "$FAILS" "$WARNS" "$RST"
  exit 2
elif [ "$WARNS" -gt 0 ]; then
  printf '%s! %d 项 WARN — 逐条人工确认后再决定是否接单%s\n' "$YLW" "$WARNS" "$RST"
  exit 1
else
  printf '%s✓ 全部通过 — 可以进入第三关(环境准备)%s\n' "$GRN" "$RST"
  exit 0
fi
