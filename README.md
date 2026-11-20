# SUPER FIVE — privat resultatcentral (fristående reserv)

**Det här är en färdig kodbas, inte en redan publicerad webbapp.** SCM påverkas inte. Webbappen kräver ett **nytt, separat Supabase-projekt**, konton och publicering på GitHub Pages innan domarna kan använda den.

## Funktioner

- Samtliga **24 officiella gruppspelsmatcher**, grupper A–D, tider och planer enligt `Super Five nytt spelschema.pdf` (21 nov 2026).
- Inloggning med Supabase Auth, admin- och domarroll.
- Domare rapporterar resultat; **bara admin kan ändra ett redan rapporterat resultat**.
- Gemensamma resultat via Supabase; realtime med 15-sekunders polling som reserv.
- Tabeller (3/1/0, målskillnad, gjorda mål), kontroll och **manuellt godkännande** av placeringar.
- Efter godkännande genereras 24 placeringsmatcher (sex per grupp, Guld/Silver/Brons/Safir). Alla 16 lag får totalt sex matcher.
- Admin kan fylla i riktiga tider och planer för placeringsmatcherna, därefter rapporterar domarna som vanligt.

## VIKTIGT: andra gruppspelets tider

Det uppladdade PDF-schemat innehåller **bara det första gruppspelet**. Appen genererar därför inga påhittade speltider eller planallokeringar för Guld/Silver/Brons/Safir: de visas som `EJ FASTSTÄLLD` tills admin fyller i det **faktiska schemat**. Matchparen är ett standardupplägg för fyra lag (alla möter alla). **Kontrollera att ordningen och planallokeringen passar arrangemanget** innan domarna börjar.

## Installation, cirka 15–30 minuter om du har kontona klara

1. Skapa ett **NYTT Supabase-projekt** (använd inte SCM-projektet eller en befintlig produktionsdatabas).
2. Öppna **SQL Editor** i det nya projektet. Klistra in hela `schema.sql` och kör en gång. Det skapar tabeller, RLS, skyddade funktioner och de 24 officiella matcherna.
3. Öppna **Authentication → Users** och skapa en användare för dig samt en för varje domare. Ange e-post/lösenord, och bekräfta e-post via Supabase-gränssnittet om så krävs. **Stäng inte av säkerheten eller RLS.**
4. För varje användare: kopiera `User UID` från Authentication. Kör i SQL Editor (byt UUID och namn):

   ```sql
   insert into public.staff(user_id,display_name,role)
   values ('DIN-ADMIN-UUID','Arrangör','admin');

   insert into public.staff(user_id,display_name,role)
   values ('DOMARE-UUID','Domare 1','referee');
   ```

   Upprepa sista satsen för varje domare. Skicka inloggningsuppgifter individuellt, inte i den gemensamma domarchatten.
5. Gå till **Project Settings → API** (i vissa versioner **Connect**). Kopiera projektets **Project URL** och **anon/publishable key**. Klistra in dem i `config.js`. **Använd ALDRIG service_role/secret key i webbkoden.**
6. Skapa ett nytt, separat GitHub-repository (t.ex. `super-five-live`) och ladda upp `index.html`, `style.css`, `app.js`, `config.js`. `schema.sql` och `README.md` kan finnas i repo men behövs inte för själva webbsidan.
7. I GitHub: **Settings → Pages → Deploy from a branch → main / (root)**. Vänta tills GitHub visar sidans adress. **GitHub Pages är publikt; inloggning och RLS skyddar data, inte URL:en.**
8. I Supabase: **Authentication → URL Configuration**, lägg till GitHub Pages-adressen som tillåten redirect URL om du använder autentiseringsflöden som kräver redirect. Den här appen använder lösenordsinloggning direkt.
9. För snabbare uppdateringar: Supabase **Database → Publications → supabase_realtime**: aktivera `matches` och `settings`. Appen hämtar ändå om data var 15:e sekund om realtime inte fungerar.
10. Testa på **två olika mobiler**: logga in som domare, rapportera ett testresultat, verifiera på adminkontot, korrigera som admin. Domare ska **inte** kunna ändra rapporterat resultat. Återställ testresultatet via SQL innan turneringen:

   ```sql
   update public.matches
   set home_score=null,away_score=null,submitted_by=null,submitted_at=null
   where phase='initial';
   ```

## Matchdag

1. Domarna loggar in på samma GitHub Pages-adress med sina egna konton.
2. De öppnar **Gruppspel**, hittar sin match via tid/plan och rapporterar exakt slutresultat.
3. Admin följer **Tabeller & kvalificering**. Efter 24 matcher granskar admin ordningen, inklusive eventuella lika tabellvärden och turneringens särskiljningsregler.
4. Admin klickar **Godkänn och skapa placeringsgrupper**. Detta skapar 24 matcher. **Det finns ingen återställningsknapp för publicering i appen**.
5. Admin öppnar **Guld · Silver · Brons · Safir** och fyller i **riktiga tider och planer** för alla matcher. Domarna rapporterar sedan resultat även här.
6. Sluttabeller visas under **Tabeller & kvalificering**. Kontrollera särskiljningsregler manuellt före prisutdelning.

## Begränsningar och säkerhet

- **Detta är en reservlösning, inte ett fullskaligt turneringssystem.** Ingen koppling till SCM eller Supercuper.se.
- Alla inloggade domare kan rapportera **alla ännu orapporterade matcher**. De är inte individuellt begränsade till en plan; matchfördelningen hanteras operativt.
- Ingen offlinekö. Internetanslutning krävs vid rapportering.
- Vid lika poäng/målskillnad/gjorda mål använder förhandsvisningen alfabetisk ordning. **Det är inte en officiell särskiljningsregel.** Admin måste kontrollera och vid behov justera placeringarna innan andra gruppspelet aktiveras.
- GitHub Pages skyddar inte källkoden eller URL:en. Supabase RLS och Auth skyddar resultaten. Publicera aldrig hemliga API-nycklar.
- För användning imorgon: avsätt tid för ett verkligt test med två enheter och säkerställ att andra gruppspelets faktiska schema finns tillgängligt.