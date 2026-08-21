/* Ustara: web-push opt-in, shared by the client and barber dashboards.
 *
 * Two rules this follows, both learned the hard way across the industry:
 *
 * 1. Never call Notification.requestPermission() on page load. A prompt with
 *    no context gets denied, and a denial is permanent — the browser will not
 *    ask again, and there is no API to undo it. So we show our own card first
 *    and only reach for the real prompt after the user taps it.
 * 2. Never nag. If they dismiss our card, we remember and stay quiet.
 *
 * The VAPID public key is not a secret — it ships in the client by design.
 * The private half lives only in the send-push Edge Function's secrets.
 */

const VAPID_PUBLIC_KEY = 'BCI3gm0EMWZzngW3VP29LPwNjGnqZuMF-4lRYRgHb21IPAALR-y3FdvYOhiB_NOSayNwaSSOt4547bVGpf5LaOc';
const PUSH_DISMISSED_KEY = 'ustara_push_dismissed';

function pushSupported(){
  return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

function pushConfigured(){
  return VAPID_PUBLIC_KEY && !VAPID_PUBLIC_KEY.startsWith('REPLACE_WITH');
}

// VAPID keys travel as base64url; PushManager wants raw bytes.
function urlBase64ToUint8Array(base64String){
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const out = new Uint8Array(raw.length);
  for(let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/* Subscribes this browser and stores it against the signed-in user.
   Safe to call repeatedly — the endpoint is unique, so an existing row is
   updated rather than duplicated (which would fire the same push twice). */
async function subscribeToPush(supabaseClient){
  if(!pushSupported() || !pushConfigured()) return { ok:false, reason:'unsupported' };
  if(Notification.permission === 'denied') return { ok:false, reason:'denied' };

  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  if(!sub){
    sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
    });
  }

  const { data: sess } = await supabaseClient.auth.getSession();
  if(!sess.session) return { ok:false, reason:'signed out' };

  const json = sub.toJSON();
  const { error } = await supabaseClient.from('push_subscriptions').upsert({
    user_id: sess.session.user.id,
    endpoint: json.endpoint,
    p256dh: json.keys.p256dh,
    auth: json.keys.auth,
    user_agent: navigator.userAgent.slice(0, 300)
  }, { onConflict: 'endpoint' });

  if(error){ console.error('Saving push subscription failed:', error); return { ok:false, reason:error.message }; }
  return { ok:true };
}

/* Renders the soft-ask card into `container` when — and only when — asking is
   still worth it: push is supported and configured, the user hasn't already
   granted or blocked it, and they haven't dismissed us before. */
function mountPushPrompt(container, supabaseClient, copy){
  if(!container) return;
  if(!pushSupported() || !pushConfigured()) return;
  if(Notification.permission !== 'default') {
    // already granted: make sure this browser is actually registered
    if(Notification.permission === 'granted') subscribeToPush(supabaseClient);
    return;
  }
  if(localStorage.getItem(PUSH_DISMISSED_KEY) === '1') return;

  const text = Object.assign({
    title: 'Bildirishnomalarni yoqing',
    body: 'Yangi so\'rov va tasdiqlar haqida darhol xabar beramiz.',
    enable: 'Yoqish',
    later: 'Keyinroq'
  }, copy || {});

  const card = document.createElement('div');
  card.className = 'push-prompt';
  card.innerHTML =
    '<div class="push-prompt__icon"><img src="/icons/icon-192.png" alt="" width="34" height="34"></div>' +
    '<div class="push-prompt__text"><strong></strong><span></span></div>' +
    '<div class="push-prompt__actions">' +
      '<button type="button" class="push-prompt__later"></button>' +
      '<button type="button" class="push-prompt__enable"></button>' +
    '</div>';
  card.querySelector('strong').textContent = text.title;
  card.querySelector('span').textContent = text.body;
  card.querySelector('.push-prompt__enable').textContent = text.enable;
  card.querySelector('.push-prompt__later').textContent = text.later;

  card.querySelector('.push-prompt__later').addEventListener('click', ()=>{
    localStorage.setItem(PUSH_DISMISSED_KEY, '1');
    card.remove();
  });
  card.querySelector('.push-prompt__enable').addEventListener('click', async ()=>{
    const btn = card.querySelector('.push-prompt__enable');
    btn.disabled = true;
    const permission = await Notification.requestPermission();
    if(permission === 'granted') await subscribeToPush(supabaseClient);
    // whichever way it went, the card has done its job
    card.remove();
  });

  container.prepend(card);
}
