import { useEffect, useState } from "react"
import { toast } from "sonner"
import { Send, TriangleAlert } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type Vehicle } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"

const ISSUES = [
  { value: "freni", label: "Freni" },
  { value: "batteria", label: "Batteria" },
  { value: "gomme", label: "Gomme" },
  { value: "luci", label: "Luci" },
  { value: "altro", label: "Altro" },
]

export function ReportVehiclePage() {
  const { session } = useAuth()
  const [vehicles, setVehicles] = useState<Vehicle[]>([])
  const [vehicleId, setVehicleId] = useState("")
  const [issueType, setIssueType] = useState("")
  const [description, setDescription] = useState("")
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    ;(async () => {
      const { data } = await supabase.from("vehicles").select("*").order("code").limit(50)
      setVehicles((data as Vehicle[]) ?? [])
    })()
  }, [])

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!vehicleId || !issueType || !description.trim()) {
      toast.error("Compila tutti i campi")
      return
    }
    setSubmitting(true)
    const { error } = await supabase.from("vehicle_reports").insert({
      user_id: session!.user.id,
      vehicle_id: vehicleId,
      issue_type: issueType,
      description: description.trim(),
    })
    setSubmitting(false)
    if (error) { toast.error(error.message); return }
    toast.success("Segnalazione inviata. Grazie!")
    setVehicleId("")
    setIssueType("")
    setDescription("")
  }

  return (
    <AppShell title="Segnala mezzo">
      <TonalCard className="mb-4">
        <div className="flex items-start gap-3">
          <div className="size-12 rounded-2xl bg-[var(--surface-low)] flex items-center justify-center">
            <TriangleAlert className="size-5 text-[var(--warning)]" />
          </div>
          <div>
            <p className="font-bold">Aiutaci a migliorare</p>
            <p className="text-sm text-[var(--muted-foreground)] mt-0.5">
              Segnala un mezzo non funzionante. La squadra tecnica interverrà appena possibile.
            </p>
          </div>
        </div>
      </TonalCard>

      <TonalCard>
        <form onSubmit={submit} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Mezzo</Label>
            <Select value={vehicleId} onValueChange={setVehicleId}>
              <SelectTrigger className="h-12 rounded-2xl bg-[var(--surface-low)] border-0">
                <SelectValue placeholder="Seleziona mezzo" />
              </SelectTrigger>
              <SelectContent>
                {vehicles.map((v) => (
                  <SelectItem key={v.id} value={v.id}>
                    {v.code} · {v.type}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Tipo problema</Label>
            <Select value={issueType} onValueChange={setIssueType}>
              <SelectTrigger className="h-12 rounded-2xl bg-[var(--surface-low)] border-0">
                <SelectValue placeholder="Seleziona problema" />
              </SelectTrigger>
              <SelectContent>
                {ISSUES.map((i) => (
                  <SelectItem key={i.value} value={i.value}>{i.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Descrizione</Label>
            <Textarea
              rows={5}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Descrivi il problema in dettaglio..."
              className="rounded-2xl bg-[var(--surface-low)] border-0 resize-none"
            />
          </div>

          <Button type="submit" disabled={submitting} className="h-12 mt-2 rounded-2xl btn-primary-grad font-bold">
            {submitting ? <Spinner /> : (<><Send className="size-4" /> Invia segnalazione</>)}
          </Button>
        </form>
      </TonalCard>
    </AppShell>
  )
}
