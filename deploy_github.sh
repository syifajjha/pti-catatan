#!/usr/bin/env bash
# Deploy halaman PTI ke GitHub Pages.
# Pakai:  GH_TOKEN=ghp_xxx bash deploy_github.sh [nama-repo]
# Token (classic) butuh scope: repo  (+ workflow kalau nanti pakai Actions)
set -euo pipefail

OWNER="syifajjha"
REPO="${1:-pti-catatan}"
TOKEN="${GH_TOKEN:?Set GH_TOKEN dulu (Personal Access Token dengan scope repo)}"
API="https://api.github.com"
AUTH=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

echo "==> 1/4 cek user token"
curl -fsS "${AUTH[@]}" "$API/user" | grep -o '"login"[^,]*' || { echo "Token tidak valid."; exit 1; }

echo "==> 2/4 buat repo $OWNER/$REPO (abaikan kalau sudah ada)"
code=$(curl -sS -o /tmp/createrepo.json -w '%{http_code}' -X POST "${AUTH[@]}" "$API/user/repos" \
  -d "{\"name\":\"$REPO\",\"description\":\"PTI - catatan ujian & bank soal UTS\",\"private\":false,\"has_issues\":true}")
case "$code" in
  201) echo "    repo dibuat." ;;
  422) echo "    repo sudah ada, lanjut." ;;
  *) echo "    gagal ($code):"; cat /tmp/createrepo.json; exit 1 ;;
esac

echo "==> 3/4 push kode"
cd "$(dirname "$0")"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "git@github.com:$OWNER/$REPO.git"
else
  git remote add origin "git@github.com:$OWNER/$REPO.git"
fi
# fallback ke HTTPS+token kalau SSH tidak tersedia
git push -u origin main 2>/dev/null || git push -u origin main \
  --repo "https://x-access-token:$TOKEN@github.com/$OWNER/$REPO.git"

echo "==> 4/4 aktifkan GitHub Pages (branch main, root)"
code=$(curl -sS -o /tmp/pages.json -w '%{http_code}' -X POST "${AUTH[@]}" "$API/repos/$OWNER/$REPO/pages" \
  -d '{"source":{"branch":"main","path":"/"}}')
if [ "$code" = "201" ] || [ "$code" = "204" ]; then
  echo "    Pages diaktifkan."
elif [ "$code" = "409" ]; then
  echo "    Pages sudah aktif, lanjut."
else
  echo "    tidak bisa otomatis ($code):"; cat /tmp/pages.json
  echo "    -> buka https://github.com/$OWNER/$REPO/settings/pages dan pilih Branch: main / (root) -> Save"
fi

URL="https://$OWNER.github.io/$REPO/"
echo "==> menunggu build pertama (maks 3 menit)"
for i in $(seq 1 36); do
  st=$(curl -sS "${AUTH[@]}" "$API/repos/$OWNER/$REPO/pages/builds/latest" | grep -o '"status": *"[a-z]*"' | head -1 | cut -d'"' -f4 || true)
  echo "    [$i] status: ${st:-unknown}"
  if [ "${st:-}" = "built" ]; then break; fi
  sleep 5
done
sleep 3
code=$(curl -sS -o /dev/null -w '%{http_code}' "$URL")
echo
echo "LINK: $URL   (HTTP $code)"
