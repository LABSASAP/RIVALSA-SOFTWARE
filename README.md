# RIVALSA-SOFTWARE
## ZooSmart - Vehicle Sharing Platform

ZooSmart è una piattaforma fullstack per la gestione di un servizio urbano di vehicle-sharing elettrico.  
L’applicazione permette agli utenti di visualizzare i mezzi disponibili nelle vicinanze, consultarne le caratteristiche, prenotarli, sbloccarli tramite app, terminare una corsa e visualizzare il costo finale.

Il sistema include inoltre una dashboard operatore per la gestione dei mezzi, delle prenotazioni, delle segnalazioni di malfunzionamento e dello stato degli utenti.

---

## Funzionalità principali

### Utente finale

L’utente può:

- visualizzare i veicoli disponibili su mappa;
- filtrare i veicoli per tipologia;
- consultare informazioni dettagliate sui mezzi;
- visualizzare batteria, autonomia, tariffa e stato del veicolo;
- prenotare un mezzo disponibile;
- sbloccare un mezzo prenotato tramite app;
- avviare e terminare una corsa;
- visualizzare il riepilogo finale della corsa;
- gestire i metodi di pagamento salvati;
- accedere alla sezione profilo/impostazioni;
- segnalare veicoli non funzionanti.

---

### Operatore

L’operatore può:

- visualizzare le segnalazioni dei veicoli;
- aggiornare lo stato delle segnalazioni;
- controllare le prenotazioni attive;
- individuare prenotazioni anomale;
- visualizzare la posizione finale dei veicoli dopo una corsa;
- modificare lo stato degli account utente;
- sospendere o bloccare utenti in caso di anomalie, frodi o comportamenti non corretti.

---

## Mappa interattiva

La piattaforma integra una mappa basata su OpenStreetMap/Leaflet.

La mappa permette di:

- visualizzare i mezzi disponibili nelle vicinanze;
- mostrare marker personalizzati per bici, monopattini e auto;
- filtrare i veicoli per categoria;
- selezionare un veicolo direttamente dalla mappa;
- visualizzare una card informativa del mezzo selezionato;
- sincronizzare mappa, lista dei veicoli e dettaglio del mezzo.

L’interfaccia è stata progettata con un approccio mobile-first, ispirato alle moderne app di mobilità urbana.

---

## Veicoli realistici e tariffe

I veicoli non sono gestiti solo come categorie generiche, ma includono modelli realistici di mezzi elettrici.

Esempi di veicoli presenti:

- Fiat 500e;
- Fiat Grande Panda Electric;
- Dacia Spring Electric;
- Citroën ë-C3;
- Peugeot e-208;
- Opel Corsa Electric;
- Volkswagen ID.3;
- Hyundai Kona Electric;
- BMW i4;
- BMW iX1;
- Tesla Model 3;
- Mercedes EQA;
- Xiaomi Electric Scooter 4;
- Ninebot Max G30;
- Decathlon Riverside 500E.

Ogni veicolo è associato a dati persistenti nel database, tra cui:

- marca;
- modello;
- nome visualizzato;
- tipologia;
- categoria tariffaria;
- tariffa di sblocco;
- tariffa al minuto;
- tariffa oraria;
- livello batteria;
- autonomia stimata;
- posizione;
- stato operativo.

---

## Logica tariffaria

Il costo di una corsa viene calcolato in base al veicolo utilizzato.

La formula utilizzata è:

finalCost = unlockFee + durationMinutes * pricePerMinute

STACK TECNOLOGICO

Il progetto utilizza il seguente stack:

Backend
NestJS;
TypeScript;
TypeORM;
PostgreSQL 16;
PostGIS;
Redis;
JWT;
bcryptjs;
Swagger.
Frontend
HTML;
CSS;
JavaScript Vanilla;
OpenStreetMap;
Leaflet.
Infrastruttura
Docker Compose;
PostgreSQL;
Redis.
Database

Il database gestisce le principali entità del sistema:

User;
Vehicle;
Reservation;
Ride;
PaymentMethod;
Payment;
VehicleReport.

I dati dei veicoli e delle tariffe sono persistiti direttamente nel database e vengono letti dal backend tramite API.

Non vengono gestiti come valori hardcoded nel frontend.
