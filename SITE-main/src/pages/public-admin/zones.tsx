import { useEffect, useMemo, useState } from "react"
import { Circle, MapContainer, TileLayer, Tooltip, useMap, useMapEvents } from "react-leaflet"
import { toast } from "sonner"
import { MapPinned, Plus, Save } from "lucide-react"
import { StatusChip, TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type UrbanZone } from "@/lib/supabase"
import { PublicAdminBody, PublicAdminHeader } from "@/pages/public-admin/layout"

type ZoneForm = {
  name: string
  description: string
  type: UrbanZone["type"]
  status: UrbanZone["status"]
  center_lat: string
  center_lng: string
  radius_meters: string
  starts_at: string
  ends_at: string
}

const DEFAULT_CENTER = { lat: 41.1175, lng: 16.872 }
const DEFAULT_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const DEFAULT_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
const tileUrl = (import.meta.env.VITE_MAP_TILE_URL as string | undefined)?.trim() || (import.meta.env.DEV ? DEFAULT_TILE_URL : "")
const tileAttribution = (import.meta.env.VITE_MAP_ATTRIBUTION as string | undefined)?.trim() || DEFAULT_ATTRIBUTION

const emptyForm: ZoneForm = {
  name: "",
  description: "",
  type: "road_work",
  status: "active",
  center_lat: String(DEFAULT_CENTER.lat),
  center_lng: String(DEFAULT_CENTER.lng),
  radius_meters: "300",
  starts_at: "",
  ends_at: "",
}

const TYPE_LABEL: Record<UrbanZone["type"], string> = {
  road_work: "Lavori urbani",
  restricted_area: "Area interdetta",
  sensitive_zone: "Zona sensibile",
}

const ZONE_TONE: Record<UrbanZone["type"], { color: string; fill: string }> = {
  road_work: { color: "#b26a00", fill: "#fff3d6" },
  restricted_area: { color: "#c62828", fill: "#ffe5e5" },
  sensitive_zone: { color: "#2e7d32", fill: "#dff4e5" },
}

export function PublicAdminZonesPage() {
  const [zones, setZones] = useState<UrbanZone[]>([])
  const [form, setForm] = useState<ZoneForm>(emptyForm)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const draftCenter = useMemo(() => {
    const lat = Number(form.center_lat)
    const lng = Number(form.center_lng)
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return DEFAULT_CENTER
    return { lat, lng }
  }, [form.center_lat, form.center_lng])

  const draftRadius = Math.max(1, Number(form.radius_meters) || 300)

  const load = async () => {
    setLoading(true)
    const { data } = await supabase.from("urban_zones").select("*").order("created_at", { ascending: false })
    setZones((data as UrbanZone[]) ?? [])
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const edit = (zone: UrbanZone) => {
    setEditingId(zone.id)
    setForm({
      name: zone.name,
      description: zone.description,
      type: zone.type,
      status: zone.status,
      center_lat: String(zone.center_lat),
      center_lng: String(zone.center_lng),
      radius_meters: String(zone.radius_meters),
      starts_at: zone.starts_at ? zone.starts_at.slice(0, 16) : "",
      ends_at: zone.ends_at ? zone.ends_at.slice(0, 16) : "",
    })
  }

  const reset = () => {
    setEditingId(null)
    setForm(emptyForm)
  }

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!form.name.trim()) {
      toast.error("Inserisci il nome zona")
      return
    }
    const lat = Number(form.center_lat)
    const lng = Number(form.center_lng)
    const radius = Number(form.radius_meters)
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || !Number.isFinite(radius)) {
      toast.error("Coordinate o raggio non validi")
      return
    }

    setSaving(true)
    const { error } = await supabase.rpc("public_admin_urban_zone_save", {
      p_name: form.name.trim(),
      p_description: form.description.trim(),
      p_type: form.type,
      p_status: form.status,
      p_center_lat: lat,
      p_center_lng: lng,
      p_radius_meters: Math.round(radius),
      p_starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
      p_ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
      p_zone_id: editingId,
    })
    setSaving(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success(editingId ? "Zona aggiornata" : "Zona creata")
    reset()
    void load()
  }

  const toggleStatus = async (zone: UrbanZone) => {
    const nextStatus = zone.status === "active" ? "inactive" : "active"
    const { error } = await supabase.rpc("public_admin_urban_zone_set_status", {
      p_zone_id: zone.id,
      p_status: nextStatus,
    })
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success(nextStatus === "active" ? "Zona attivata" : "Zona disattivata")
    void load()
  }

  return (
    <>
      <PublicAdminHeader title="Gestione zone" subtitle="Crea e aggiorna lavori urbani, aree interdette e zone sensibili." />
      <PublicAdminBody>
        <div className="grid gap-5 xl:grid-cols-[430px_1fr]">
          <TonalCard>
            <form onSubmit={submit} className="flex flex-col gap-3">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="label-sm text-[var(--muted-foreground)]">{editingId ? "MODIFICA" : "NUOVA ZONA"}</p>
                  <h2 className="mt-1 text-xl font-bold">{editingId ? "Aggiorna zona" : "Configura area"}</h2>
                </div>
                {editingId && <Button type="button" variant="ghost" onClick={reset} className="rounded-2xl bg-[var(--surface-low)]">Nuova</Button>}
              </div>

              <Field label="Nome">
                <Input value={form.name} onChange={(event) => setForm({ ...form, name: event.target.value })} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]" />
              </Field>
              <Field label="Descrizione">
                <Textarea value={form.description} onChange={(event) => setForm({ ...form, description: event.target.value })} rows={3} className="resize-none rounded-2xl border-0 bg-[var(--surface-low)]" />
              </Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Tipo">
                  <Select value={form.type} onValueChange={(value) => setForm({ ...form, type: value as UrbanZone["type"] })}>
                    <SelectTrigger className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="road_work">Lavori urbani</SelectItem>
                      <SelectItem value="restricted_area">Area interdetta</SelectItem>
                      <SelectItem value="sensitive_zone">Zona sensibile</SelectItem>
                    </SelectContent>
                  </Select>
                </Field>
                <Field label="Stato">
                  <Select value={form.status} onValueChange={(value) => setForm({ ...form, status: value as UrbanZone["status"] })}>
                    <SelectTrigger className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="active">Attiva</SelectItem>
                      <SelectItem value="inactive">Inattiva</SelectItem>
                    </SelectContent>
                  </Select>
                </Field>
              </div>
              <div className="grid grid-cols-3 gap-3">
                <Field label="Lat">
                  <Input value={form.center_lat} onChange={(event) => setForm({ ...form, center_lat: event.target.value })} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)] font-mono" />
                </Field>
                <Field label="Lng">
                  <Input value={form.center_lng} onChange={(event) => setForm({ ...form, center_lng: event.target.value })} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)] font-mono" />
                </Field>
                <Field label="Raggio m">
                  <Input value={form.radius_meters} onChange={(event) => setForm({ ...form, radius_meters: event.target.value.replace(/\D/g, "") })} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)] font-mono" />
                </Field>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Inizio">
                  <Input type="datetime-local" value={form.starts_at} onChange={(event) => setForm({ ...form, starts_at: event.target.value })} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]" />
                </Field>
                <Field label="Fine">
                  <Input type="datetime-local" value={form.ends_at} onChange={(event) => setForm({ ...form, ends_at: event.target.value })} className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]" />
                </Field>
              </div>
              <div className="rounded-2xl bg-[var(--surface-low)] p-3 text-xs font-semibold leading-relaxed text-[var(--muted-foreground)]">
                Clicca sulla mappa per impostare il centro della zona. Il sistema usa coordinate e raggio, senza poligoni complessi.
              </div>
              <Button type="submit" disabled={saving} className="mt-2 h-12 rounded-2xl btn-primary-grad font-bold">
                {saving ? <Spinner /> : editingId ? (<><Save className="size-4" /> Salva modifiche</>) : (<><Plus className="size-4" /> Crea zona</>)}
              </Button>
            </form>
          </TonalCard>

          <div className="grid gap-5">
            <TonalCard className="p-0">
              <div className="flex items-center justify-between gap-3 px-5 pt-5">
                <div>
                  <p className="label-sm text-[var(--muted-foreground)]">MAPPA ZONE</p>
                  <h2 className="mt-1 text-xl font-bold">Overlay urbani</h2>
                </div>
                <div className="flex items-center gap-2 rounded-2xl bg-[var(--surface-low)] px-3 py-2 text-sm font-bold text-[var(--primary)]">
                  <MapPinned className="size-4" />
                  {zones.length}
                </div>
              </div>
              <div className="mt-4 h-[520px] overflow-hidden rounded-b-3xl bg-[var(--surface-low)]">
                <ZoneMap
                  zones={zones}
                  draftCenter={draftCenter}
                  draftRadius={draftRadius}
                  draftType={form.type}
                  editingId={editingId}
                  onPick={(lat, lng) => setForm({ ...form, center_lat: lat.toFixed(5), center_lng: lng.toFixed(5) })}
                />
              </div>
            </TonalCard>

            {loading ? (
              <div className="flex justify-center py-10"><Spinner /></div>
            ) : (
              <div className="grid gap-3">
                {zones.map((zone) => (
                  <TonalCard key={zone.id} active={zone.id === editingId}>
                    <div className="flex items-start justify-between gap-4">
                      <div className="min-w-0">
                        <p className="label-sm text-[var(--muted-foreground)]">{TYPE_LABEL[zone.type]}</p>
                        <h3 className="mt-1 text-lg font-bold">{zone.name}</h3>
                        <p className="mt-1 text-sm text-[var(--muted-foreground)]">{zone.description || "Nessuna descrizione"}</p>
                        <p className="mt-2 font-mono text-xs text-[var(--muted-foreground)]">
                          {zone.center_lat.toFixed(5)}, {zone.center_lng.toFixed(5)} - {zone.radius_meters} m
                        </p>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-2">
                        <StatusChip status={zone.status} />
                        <Button onClick={() => edit(zone)} variant="ghost" size="sm" className="rounded-xl bg-[var(--surface-low)]">Modifica</Button>
                        <Button onClick={() => toggleStatus(zone)} variant="ghost" size="sm" className="rounded-xl bg-[var(--surface-high)]">
                          {zone.status === "active" ? "Disattiva" : "Attiva"}
                        </Button>
                      </div>
                    </div>
                  </TonalCard>
                ))}
              </div>
            )}
          </div>
        </div>
      </PublicAdminBody>
    </>
  )
}

function ZoneMap({
  zones,
  draftCenter,
  draftRadius,
  draftType,
  editingId,
  onPick,
}: {
  zones: UrbanZone[]
  draftCenter: { lat: number; lng: number }
  draftRadius: number
  draftType: UrbanZone["type"]
  editingId: string | null
  onPick: (lat: number, lng: number) => void
}) {
  return (
    <MapContainer center={[draftCenter.lat, draftCenter.lng]} zoom={14} className="h-full w-full" scrollWheelZoom>
      {tileUrl && <TileLayer attribution={tileAttribution} url={tileUrl} />}
      <DraftCenterSync center={draftCenter} />
      <ZoneClickHandler onPick={onPick} />
      {zones.map((zone) => {
        const tone = ZONE_TONE[zone.type]
        return (
          <Circle
            key={zone.id}
            center={[zone.center_lat, zone.center_lng]}
            radius={zone.radius_meters}
            pathOptions={{
              color: tone.color,
              fillColor: tone.fill,
              fillOpacity: zone.status === "active" ? 0.22 : 0.08,
              opacity: zone.status === "active" ? 0.78 : 0.32,
              weight: zone.id === editingId ? 4 : 2,
            }}
          >
            <Tooltip direction="top" opacity={0.95}>
              {TYPE_LABEL[zone.type]}: {zone.name}
            </Tooltip>
          </Circle>
        )
      })}
      <Circle
        center={[draftCenter.lat, draftCenter.lng]}
        radius={draftRadius}
        pathOptions={{
          color: ZONE_TONE[draftType].color,
          fillColor: ZONE_TONE[draftType].fill,
          fillOpacity: 0.16,
          opacity: 0.9,
          dashArray: "8 8",
          weight: 3,
        }}
      >
        <Tooltip direction="top" opacity={0.95}>Zona in modifica</Tooltip>
      </Circle>
    </MapContainer>
  )
}

function DraftCenterSync({ center }: { center: { lat: number; lng: number } }) {
  const map = useMap()

  useEffect(() => {
    map.setView([center.lat, center.lng], Math.max(map.getZoom(), 14), { animate: true })
  }, [center.lat, center.lng, map])

  return null
}

function ZoneClickHandler({ onPick }: { onPick: (lat: number, lng: number) => void }) {
  useMapEvents({
    click(event) {
      onPick(event.latlng.lat, event.latlng.lng)
    },
  })
  return null
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label className="label-sm text-[var(--muted-foreground)]">{label}</Label>
      {children}
    </div>
  )
}
