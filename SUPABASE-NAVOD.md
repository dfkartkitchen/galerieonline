# Otevřená galerie – nastavení Supabase

Návod, jak z galerie udělat sdílený online sál. Celé to zabere asi 15 minut a stačí bezplatný tarif Supabase.

Adresa webu: **https://glowing-muffin-10037c.netlify.app**

---

## 1. Založte projekt

1. Přihlaste se na <https://supabase.com/dashboard> (třeba přes GitHub).
2. **New project**. Vyberte organizaci s tarifem **Free**.
3. Vyplňte:
   - **Name:** `galerieonline`
   - **Database Password:** vygenerujte a uložte si ho do správce hesel (do webu ho nedáváte).
   - **Region:** `Central EU (Frankfurt)` (nejblíž Česku).
4. **Create new project** a počkejte asi 2 minuty, než se projekt připraví.

## 2. Spusťte SQL

1. V levém menu **SQL Editor** → **New query**.
2. Zkopírujte celý obsah souboru [`supabase/schema.sql`](supabase/schema.sql), vložte ho a klikněte na **Run**.
3. Má skončit hláškou *Success. No rows returned*. Skript můžete spustit i opakovaně, nic nerozbije.

Skript vytvoří:

- tabulky `paintings`, `hidden_samples` a `admins` se zapnutým RLS,
- limit 3 obrazy na uživatele,
- Realtime publikaci pro `paintings` a `hidden_samples`,
- bucket `paintings` ve Storage (veřejné čtení, max. 5 MB, jen JPEG/PNG/WebP) a pravidla, kdo smí nahrávat a mazat.

**Kontrola:**

- **Table Editor**: jsou tam tři tabulky a u každé je štítek *RLS enabled*.
- **Storage**: je tam bucket `paintings` označený *Public*.

**Když SQL selže na části „Storage“** (chyba typu *must be owner of table objects*):

1. Bucket vytvořte ručně: **Storage** → **New bucket** → název `paintings`. Zapněte **Public bucket**, u **Restrict file size** nastavte `5 MB` a do **Allowed MIME types** zadejte `image/jpeg, image/png, image/webp`.
2. Tři storage policies přidejte přes **Storage** → **Policies** → `paintings` → **New policy** → **For full customization**:

   | Název | Operace | Role | Výraz |
   |---|---|---|---|
   | nahrát do vlastní složky | INSERT | authenticated | `bucket_id = 'paintings' and (storage.foldername(name))[1] = auth.uid()::text` |
   | číst vlastní nebo admin | SELECT | authenticated | `bucket_id = 'paintings' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())` |
   | smazat vlastní nebo admin | DELETE | authenticated | stejný výraz jako SELECT |

## 3. Zapněte přihlášení e-mailem (magic link)

1. **Authentication** → **Sign In / Providers** → **Email**.
2. **Enable Email provider** musí být zapnuté (výchozí stav).
3. **Confirm email** nechte zapnuté. U magic linku první kliknutí na odkaz zároveň potvrdí e-mail.
4. **Save**.

> ⚠️ **Důležité – e-maily.** Vestavěná e-mailová služba Supabase je jen na zkoušení:
>
> - pošle zhruba **2 e-maily za hodinu** pro celý projekt,
> - doručuje **jen na adresy členů vašeho týmu** v Supabase (Organization → Team).
>
> Vy sami se tedy přihlásit můžete. **Cizí návštěvníci ale přihlašovací odkaz nedostanou, dokud nenastavíte vlastní SMTP.**
>
> Pro ostrý provoz:
>
> 1. **Authentication** → **Emails** → **SMTP Settings** → **Enable custom SMTP**.
> 2. Vyplňte údaje od poskytovatele, např. Brevo, Resend, Postmark nebo SMTP od vašeho hostingu. Brevo i Resend mají bezplatný tarif.
> 3. Pak v **Authentication** → **Rate Limits** zvyšte *Rate limit for sending emails* podle potřeby.
>
> Volitelně si v **Authentication** → **Emails** → **Templates** → *Magic Link* přeložte text e-mailu do češtiny.

## 4. Nastavte adresu webu (Site URL a Redirect URLs)

1. **Authentication** → **URL Configuration**.
2. **Site URL:** `https://glowing-muffin-10037c.netlify.app`
3. **Redirect URLs** → **Add URL**, přidejte postupně:
   - `https://glowing-muffin-10037c.netlify.app/**`
   - `http://localhost:3000/**` (jen pro lokální test přes `npx serve .`, později ho můžete smazat)
4. **Save changes**.

Bez tohoto kroku by odkaz z e-mailu vedl jinam a přihlášení by nefungovalo.

## 5. Zkopírujte URL a anon key do `config.js`

1. **Project Settings** (ozubené kolo) → **Data API**: zkopírujte **Project URL** (`https://xxxx.supabase.co`).
2. **Project Settings** → **API Keys**: zkopírujte klíč **`anon` `public`**. V novějším rozhraní je to **Publishable key** (`sb_publishable_…`), ten funguje také.
3. Vložte obojí do souboru `config.js` v kořeni repozitáře:

   ```js
   window.GALERIE_CONFIG = {
     supabaseUrl: "https://xxxx.supabase.co",
     supabaseAnonKey: "eyJhbGciOi…"
   };
   ```

> 🔒 Anon/publishable klíč je veřejný a patří do webu. Data chrání RLS pravidla ze `schema.sql`.
> **Nikdy** do webu ani do repozitáře nedávejte klíč **`service_role`** / **Secret key**, ten obchází všechna pravidla.

Když `config.js` chybí nebo má prázdné hodnoty, galerie běží dál v místním režimu (obrazy jen v prohlížeči, bez ostatních návštěvníků).

## 6. Přidejte se mezi správce

Správce může sundat cizí obrazy i ukázková díla.

1. Nejdřív se jednou přihlaste na webu: **Vystavit obraz** → zadejte e-mail → klikněte na odkaz z e-mailu. Tím vznikne váš účet.
2. Ověřte to v **Authentication** → **Users**, kde se má objevit vaše adresa.
3. V **SQL Editoru** spusťte (s vaší adresou):

   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'vas@email.cz'
   on conflict do nothing;
   ```

4. Obnovte stránku galerie. U každého obrazu teď uvidíte tlačítko pro sundání.

Správce odeberete takto:

```sql
delete from public.admins
where user_id = (select id from auth.users where email = 'vas@email.cz');
```

## Limity bezplatného tarifu (pro představu)

| Co | Limit Free |
|---|---|
| Realtime – současně připojení | 200 |
| Realtime – zprávy za sekundu (celý projekt) | 100 |
| Realtime – presence zprávy za sekundu | 20 |
| Databáze | 500 MB |
| Storage | 1 GB |
| Neaktivní projekt | po 7 dnech bez provozu se pozastaví, v dashboardu ho jedním klikem obnovíte |

Galerie posílá polohu jen při pohybu a s omezenou frekvencí, aby se do těchto limitů vešla i s několika desítkami lidí najednou.
