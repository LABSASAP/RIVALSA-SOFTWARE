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
4. Avvia il progetto:
   `npm run dev`

## Account di test

1. Registra un account utente dalla schermata `/login`.
2. Registra un secondo account da usare come operatore.
3. In Supabase SQL Editor promuovi il secondo account:

```sql
update profiles
set role = 'operator'
where email = 'operator@tuodominio.test';
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
7. Accedi come operatore e verifica `/operator`, `/operator/reservations`, `/operator/end-location` e `/operator/users`.
