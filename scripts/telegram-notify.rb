#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Telegram Bot API notifier — pošalji HTML poruku u grupu.
#   echo "<b>zdravo</b>" | ./scripts/telegram-notify.rb
#   ./scripts/telegram-notify.rb --text '<b>zdravo</b>'
#   ./scripts/telegram-notify.rb --dry-run --text '…'   # ispiši, ne šalji
#
# Tajne iz .env (gitignored): TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID.
# Bez njih je no-op s exit 0 — notifikacija NIKAD ne smije oboriti build.
#
# Port obrazaca iz ms-toptal-projects/tools/job-watch/src/notify.js:
#   * chunkanje na 3800 znakova (Telegram hard limit je 4096),
#   * retry na 429/5xx uz `retry_after`,
#   * `migrate_to_chat_id` — grupa promoviranjem u supergrupu DOBIJE NOVI id i
#     stari zauvijek vraća 400; pratimo novi i zapišemo ga u .env.
#
# Dodatak specifičan za ovaj repo: REDAKCIJA. Grupa je javna, a build logovi
# mogu sadržavati `--dart-define=SUPABASE_ANON_KEY=…` i slično, pa se sve
# vrijednosti iz .env (i JWT-oliki nizovi) maskiraju prije slanja.
require 'json'
require 'net/http'
require 'uri'

ROOT     = File.expand_path('..', __dir__)
ENV_FILE = File.join(ROOT, '.env')
API      = 'https://api.telegram.org'
LIMIT    = 3800

# ── .env ─────────────────────────────────────────────────────────────────────
def load_env_file
  return {} unless File.exist?(ENV_FILE)

  File.readlines(ENV_FILE).each_with_object({}) do |line, h|
    next if line.strip.empty? || line.strip.start_with?('#')

    k, v = line.chomp.split('=', 2)
    h[k.strip] = v.to_s.strip.gsub(/\A["']|["']\z/, '') if k && v
  end
end

FILE_ENV = load_env_file
def cfg(key) = ENV[key] || FILE_ENV[key]

# ── redakcija ────────────────────────────────────────────────────────────────
# Maskiraj: (1) svaku vrijednost iz .env dulju od 8 znakova, (2) JWT-olike
# nizove, (3) desnu stranu bilo kojeg --dart-define=KEY=VALUE.
def redact(text)
  out = text.dup
  FILE_ENV.each do |k, v|
    next if v.to_s.length < 8
    # *_URL su javni endpointi — maskiranje bi samo unakazilo poruku.
    next if k.end_with?('_URL') || k == 'TELEGRAM_CHAT_ID'

    out = out.gsub(v, "«redacted:#{k}»")
  end
  out = out.gsub(/eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}(\.[A-Za-z0-9_\-]+)?/, '«redacted:jwt»')
  out = out.gsub(/(--dart-define=)([A-Za-z0-9_]+)=\S+/, '\1\2=«redacted»')
  out.gsub(/(bot)\d{6,}:[A-Za-z0-9_\-]{20,}/, '\1«redacted:telegram-token»')
end

# ── slanje ───────────────────────────────────────────────────────────────────
def adopt_migrated_chat_id(new_id)
  return unless File.exist?(ENV_FILE)

  src = File.read(ENV_FILE)
  File.write(ENV_FILE,
             if src =~ /^TELEGRAM_CHAT_ID=.*$/
               src.sub(/^TELEGRAM_CHAT_ID=.*$/, "TELEGRAM_CHAT_ID=#{new_id}")
             else
               "#{src.sub(/\n?\z/, "\n")}TELEGRAM_CHAT_ID=#{new_id}\n"
             end)
  warn "   ↪ grupa je postala supergrupa — novi chat_id #{new_id} (zapisan u .env)"
rescue StandardError
  # .env nezapisiv — id u memoriji spašava ovaj run
end

def post_message(token, chat_id, text, tries: 4, base: 2.0)
  last = nil
  1.upto(tries) do |attempt|
    uri = URI("#{API}/bot#{token}/sendMessage")
    res = Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 20, read_timeout: 40) do |http|
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = JSON.dump(chat_id: chat_id, text: text, parse_mode: 'HTML',
                           disable_web_page_preview: true)
      http.request(req)
    end
    body = (JSON.parse(res.body.to_s) rescue {})
    return [true, chat_id] if res.code.to_i == 200 && body['ok']

    migrated = body.dig('parameters', 'migrate_to_chat_id')
    if migrated && migrated.to_s != chat_id.to_s
      adopt_migrated_chat_id(migrated)
      chat_id = migrated # sljedeći attempt ide na novi id
      next
    end
    if (res.code.to_i == 429 || res.code.to_i >= 500) && attempt < tries
      wait = body.dig('parameters', 'retry_after').to_f
      sleep(wait.positive? ? wait : base * attempt)
      next
    end
    last = "Telegram #{res.code}: #{body['description'] || res.body}"
    break
  rescue StandardError => e
    last = e.message
    sleep(base * attempt) if attempt < tries
  end
  [false, last]
end

# Razlomi na <=LIMIT komada po praznim/novim redovima, da se ne reže unutar taga.
def chunk(text)
  return [text] if text.length <= LIMIT

  chunks = []
  cur = ''
  text.split("\n").each do |line|
    if cur.length + line.length + 1 > LIMIT
      chunks << cur unless cur.empty?
      cur = line
    else
      cur = cur.empty? ? line : "#{cur}\n#{line}"
    end
  end
  chunks << cur unless cur.empty?
  chunks
end

# ── main ─────────────────────────────────────────────────────────────────────
dry = ARGV.delete('--dry-run')
idx = ARGV.index('--text')
raw = if idx then ARGV[idx + 1].to_s else $stdin.read end
raw = raw.to_s.strip
exit 0 if raw.empty?

message = redact(raw)

if dry
  puts message
  exit 0
end

token   = cfg('TELEGRAM_BOT_TOKEN')
chat_id = cfg('TELEGRAM_CHAT_ID')
if token.to_s.empty? || chat_id.to_s.empty?
  warn 'telegram-notify: TELEGRAM_BOT_TOKEN/TELEGRAM_CHAT_ID nisu u .env — preskačem (no-op).'
  exit 0
end

ok_all = true
chunk(message).each do |part|
  ok, info = post_message(token, chat_id, part)
  unless ok
    warn "telegram-notify: #{info}"
    ok_all = false
    break
  end
  chat_id = info
end
# Namjerno exit 0 i na neuspjehu: notifikacija je non-fatal.
warn 'telegram-notify: poruka NIJE poslana (vidi gore).' unless ok_all
exit 0
