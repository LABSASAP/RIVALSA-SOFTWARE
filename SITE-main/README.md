# ZooSmart

[![Open in Bolt](https://bolt.new/static/open-in-bolt.svg)](https://bolt.new/~/sb1-gl6x9enh)

## Setup locale

1. Installa le dipendenze:
   `npm install`
2. Crea `.env` partendo da `.env.example` e inserisci:
   `VITE_SUPABASE_URL`
   `VITE_SUPABASE_ANON_KEY`
3. In Supabase SQL Editor esegui, in ordine:
   `supabase/migrations/20260514155541_zoosmart_initial_schema.sql`
   `supabase/migrations/20260515170000_zoosmart_local_bootstrap.sql`
   `supabase/migrations/20260524114500_vehicle_catalog_pricing_fix.sql`
   `supabase/migrations/20260527120000_sprint2.sql`
   `supabase/migrations/20260527153000_public_admin_reports.sql`
   `supabase/migrations/20260527170000_operator_sprint2.sql`
   `supabase/migrations/20260527200000_security_rls_grants.sql`
   `supabase/migrations/20260527201000_postgis_spatial_ref_sys_api_revoke.sql`
   `supabase/migrations/20260527202000_fix_credit_wallet_ambiguous_user_id.sql`
   `supabase/migrations/20260527203000_add_ride_pauses_maintenance_tasks.sql`
   opzionale demo: `supabase/seed_realistic_vehicles.sql` e `supabase/seed_sprint2_demo.sql`
4. Avvia il progetto:
   `npm run dev`

## Account di test

### Seed development automatico

Gli account completi non erano recuperabili dal repository: i seed esistenti promuovevano solo profili gia presenti in Supabase Auth. Per un ambiente development puoi generare un seed SQL idempotente:

```bash
npm run seed:test-users
```

Il comando usa `bcryptjs`, genera `supabase/seed_test_users_dev.generated.sql` con soli hash bcrypt e stampa in console le credenziali demo. Esegui il SQL generato nel Supabase SQL Editor dopo tutte le migration Sprint 2. Il seed non elimina utenti: se trova la stessa email aggiorna password, metadata Auth, `profiles.role` e `profiles.status`.

| Ruolo | Email | Password | Stato |
|------|-------|----------|-------|
| user | user@zoosmart.local | Password123! | active |
| operator | operator@zoosmart.local | Password123! | active |
| public_admin | admin.comune@zoosmart.local | Password123! | active |

Il ruolo viene scritto anche in `raw_user_meta_data.role` e `raw_app_meta_data.zoosmart_role`, cosi il token emesso al login contiene il dato nei metadata JWT oltre al ruolo applicativo in `profiles`.

### Procedura manuale

1. Registra un account utente dalla schermata `/login`.
2. Registra un secondo account da usare come operatore.
3. In Supabase SQL Editor promuovi il secondo account:

```sql
update profiles
set role = 'operator'
where email = 'operator@tuodominio.test';
```

4. Registra un terzo account da usare come amministrazione comunale e promuovilo:

```sql
update profiles
set role = 'public_admin'
where email = 'admin@tuodominio.test';
```

Se avevi creato utenti prima della migration iniziale, esegui anche il backfill:

```sql
insert into profiles (id, email, display_name, role, status)
select
  u.id,
  coalesce(u.email, ''),
  coalesce(u.raw_user_meta_data->>'display_name', split_part(coalesce(u.email, ''), '@', 1)),
  coalesce(u.raw_user_meta_data->>'role', 'user'),
  'active'
from auth.users u
left join profiles p on p.id = u.id
where p.id is null;
```

## Flusso minimo da verificare

1. Accedi come utente normale.
2. Verifica che `/nearby` mostri i mezzi seedati.
3. Prenota un mezzo e sbloccalo.
4. Aggiungi un metodo di pagamento da `/payment-methods`.
5. Termina la corsa e controlla il riepilogo.
6. Invia una segnalazione da `/report`.
7. Verifica crediti e supporto da `/credits` e `/support`.
8. Accedi come operatore e verifica `/operator`, `/operator/reservations`, `/operator/support`, `/operator/fleet`, `/operator/tracking`, `/operator/maintenance`, `/operator/end-location` e `/operator/users`.
9. Accedi come amministrazione comunale e verifica `/public-admin`, `/public-admin/zones` e `/public-admin/routes`.

## Verifica Sprint 2 Amministrazione Comunale

1. Accedi con un profilo `public_admin`: il redirect deve portare a `/public-admin`.
2. In `/public-admin` usa il filtro periodo e verifica frequenza mezzi, report mobilita e stato flotta.
3. In `/public-admin/zones` crea una zona `road_work`, una `restricted_area` e una `sensitive_zone`; devono apparire come cerchi sulla mappa e persistere in `urban_zones`.
4. In `/public-admin/routes` verifica classifica, grafico e mappa delle tratte dopo aver completato corse con start/end location.
5. Accedi come `user` o `operator` e prova una rotta `/public-admin/*`: deve reindirizzare alla home del ruolo.
6. Come utente, apri `/nearby`: zone sensibili/interdette attive devono apparire sulla mappa e generare avvisi se impattano percorso o mezzo selezionato.

## Verifica Sprint 2 Operatore

1. Accedi con un profilo `operator`: il redirect deve portare a `/operator`.
2. Verifica `/operator/fleet`: mappa distribuzione, filtri stato/categoria, conteggi, alert bassa disponibilita e blocco/sblocco remoto.
3. Verifica `/operator/maintenance`: priorita, motivazioni, segnalazioni aperte e azioni manutenzione.
4. Avvia una corsa come utente, attendi il salvataggio posizioni simulate, poi verifica `/operator/tracking` con mappa, ultima posizione e storico.
5. Termina una corsa fuori da `restricted_area`: l'utente deve ricevere il bonus punti e l'operatore deve vederlo in `/operator/bonuses`.
6. Da `/operator/bonuses`, prova un bonus manuale su una corsa completata non ancora premiata.
7. Crea un ticket da `/support` come utente e verifica in `/operator/support` lettura, risposta, cambio stato e chiusura.
8. Accedi come `user` o `public_admin` e prova `/operator/*`: deve reindirizzare alla home del ruolo.

## Supabase Security Advisor

Esegui sempre `supabase/migrations/20260527200000_security_rls_grants.sql` dopo le migration Sprint 2. Questa migration abilita RLS in modo difensivo sulle tabelle applicative ZooSmart, rimuove accessi anonimi e aggiunge grant espliciti minimi per il Data API sulle sole tabelle usate dal frontend. Se la esegui per errore prima di Sprint 2, non fallisce sulle tabelle mancanti ma devi rieseguirla dopo Sprint 2 per applicare grant e RLS anche alle nuove tabelle.

Per una scaletta completa da incollare nel Supabase SQL Editor, usa `supabase/security_advisor_checklist.sql`.

Prima e dopo la migration puoi verificare le tabelle `public` senza RLS:

```sql
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and c.relrowsecurity = false
order by c.relname;
```

Verifica i grant Data API effettivi:

```sql
select
  table_schema,
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;
```

Verifica le RPC esposte:

```sql
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  r.rolname as grantee,
  p.proacl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
left join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a on true
left join pg_roles r on r.oid = a.grantee
where n.nspname = 'public'
  and r.rolname in ('anon', 'authenticated', 'service_role')
order by p.proname, args, grantee;
```

Dopo l'applicazione, il Security Advisor non deve piu mostrare `rls_disabled_in_public` per tabelle applicative ZooSmart. Se la query restituisce solo `spatial_ref_sys`, non correggerla con questa migration: e una tabella gestita dall'estensione PostGIS e va trattata come tema extension/schema seguendo la procedura Supabase dedicata o contattando il supporto Supabase.

### PostGIS `spatial_ref_sys`

ZooSmart usa PostGIS per coordinate e distanza, ma il frontend non deve leggere direttamente `public.spatial_ref_sys`. Dopo la security migration principale puoi applicare:

`supabase/migrations/20260527201000_postgis_spatial_ref_sys_api_revoke.sql`

Questa migration revoca solo i grant Data API da `PUBLIC`, `anon` e `authenticated` su `spatial_ref_sys`. Non abilita RLS e non sposta PostGIS, perche la tabella appartiene all'estensione. Il revoke da `PUBLIC` e importante perche i privilegi ereditati possono apparire come grant effettivi su `anon` e `authenticated`.

Verifica owner e stato RLS:

```sql
select
  n.nspname as schema_name,
  c.relname as table_name,
  pg_get_userbyid(c.relowner) as owner,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'spatial_ref_sys';
```

Verifica grant residui su `spatial_ref_sys`:

```sql
select
  table_schema,
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'spatial_ref_sys'
  and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
order by grantee, privilege_type;
```

Risultato atteso dopo la migration: nessuna riga per `PUBLIC`, `anon` o `authenticated`; eventuali righe per `service_role` sono accettabili. Se il Security Advisor continua a segnalare `spatial_ref_sys` solo per RLS disabilitata, la soluzione completa e spostare PostGIS in uno schema dedicato seguendo la procedura Supabase, da fare come intervento separato.

Se dopo il revoke `anon` e `authenticated` risultano ancora con privilegi effettivi, verifica se puoi assumere l'owner `supabase_admin`:

```sql
select
  current_user,
  session_user,
  pg_has_role(current_user, 'supabase_admin', 'member') as can_set_supabase_admin,
  pg_has_role(current_user, 'supabase_admin', 'usage') as can_use_supabase_admin;
```

Se `can_set_supabase_admin` e `true`, puoi eseguire in una singola sessione:

```sql
begin;
set local role supabase_admin;
revoke all privileges on table public.spatial_ref_sys from public;
revoke all privileges on table public.spatial_ref_sys from anon;
revoke all privileges on table public.spatial_ref_sys from authenticated;
commit;
```

Poi verifica i privilegi effettivi:

```sql
select
  role_name,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'SELECT') as can_select,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'INSERT') as can_insert,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'UPDATE') as can_update,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'DELETE') as can_delete
from (values ('anon'), ('authenticated'), ('service_role')) as roles(role_name);
```

Se `can_set_supabase_admin` e `false`, non forzare RLS su `spatial_ref_sys`: considera chiusa la sicurezza delle tabelle ZooSmart se le query applicative restituiscono zero problemi e tratta il residuo PostGIS come intervento separato. In quel caso apri supporto Supabase indicando che `public.spatial_ref_sys` e owned da `supabase_admin` e che `postgres` non puo assumere quel ruolo, oppure pianifica una migration dedicata per spostare PostGIS in uno schema separato e ritestare tutte le RPC `ST_*`.
