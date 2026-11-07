// Settings → Secure Logins: a Bot can sign in to a saved site after you approve; the app types the password, the Bot never sees it.
const el = (tag, className = '', text = '') => { const node = document.createElement(tag); if (className) node.className = className; if (text) node.textContent = text; return node; };

export async function renderSecureLogins({ bridge, result, toast, page }) {
  if (!bridge.loginsList) { page.append(el('p', 'muted', 'Secure logins are available in the installed app.')); return; }
  const wrap = el('div', 'voice-settings');
  wrap.append(el('p', 'muted', 'Save a login here, then ask a Bot to sign in. Each time, a dialog shows the site and account and you approve it. OpenGrokBot types the password into the page itself: the Bot and its AI provider never see it, and it never appears in the chat. A login only works on the website you save it for and its subdomains. Verification codes and passkeys are not handled. Passwords are encrypted on this PC.'));
  const fields = {};
  const row = (label, control) => { const wrapRow = el('label', 'voice-row'); wrapRow.append(el('span', '', label), control); return wrapRow; };
  for (const [key, label, type, placeholder] of [['label', 'Name', 'text', 'For example ESPN'], ['url', 'Website', 'text', 'https://www.espn.com/login'], ['username', 'Username or email', 'text', ''], ['password', 'Password', 'password', '']]) {
    const input = el('input'); input.type = type; input.placeholder = placeholder; input.autocomplete = 'off'; fields[key] = input; wrap.append(row(label, input));
  }
  const itemInput = el('input'); itemInput.placeholder = 'Exact 1Password item name'; itemInput.autocomplete = 'off';
  const itemRow = row('1Password item (optional)', itemInput);
  wrap.append(itemRow, el('p', 'muted', 'Fill in a 1Password item name instead of a username and password to use 1Password (its command-line tool, op, must be installed). Nothing but the item name is saved here.'));
  const list = el('div', 'voice-settings');
  const save = el('button', '', 'Save login'); save.type = 'button';
  const refresh = async () => {
    list.replaceChildren();
    let logins = []; try { logins = await result(bridge.loginsList()); } catch (error) { toast(error.message); }
    if (!logins.length) list.append(el('p', 'muted', 'No logins saved yet.'));
    for (const login of logins) {
      const line = el('div', 'voice-key'); const remove = el('button', '', 'Remove'); remove.type = 'button';
      remove.addEventListener('click', async () => { try { await result(bridge.loginsRemove(login.id)); toast(`Removed ${login.label}.`); refresh(); } catch (error) { toast(error.message); } });
      line.append(el('span', '', `${login.label} · ${login.onePassword ? '1Password' : login.username} · ${login.host}`), remove); list.append(line);
    }
  };
  save.addEventListener('click', async () => {
    try {
      if (itemInput.value.trim() && bridge.loginsAddOnePassword) await result(bridge.loginsAddOnePassword({ label: fields.label.value, url: fields.url.value, item: itemInput.value }));
      else await result(bridge.loginsAdd({ label: fields.label.value, url: fields.url.value, username: fields.username.value, password: fields.password.value }));
      itemInput.value = '';
      for (const input of Object.values(fields)) input.value = '';
      toast('Saved on this PC, encrypted.'); refresh();
    } catch (error) { toast(error.message); }
  });
  wrap.append(save);
  page.append(wrap, el('h3', '', 'Saved logins'), list);
  refresh();
}
