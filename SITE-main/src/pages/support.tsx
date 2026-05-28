import { useEffect, useMemo, useState } from "react"
import { Link } from "react-router-dom"
import { toast } from "sonner"
import { CheckCircle2, Headphones, RefreshCw, Send, TriangleAlert } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { StatusChip, TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type SupportMessage, type SupportTicket } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"

export function SupportPage() {
  const { session } = useAuth()
  const userId = session?.user.id
  const [tickets, setTickets] = useState<SupportTicket[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [messages, setMessages] = useState<SupportMessage[]>([])
  const [subject, setSubject] = useState("")
  const [newMessage, setNewMessage] = useState("")
  const [reply, setReply] = useState("")
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [closing, setClosing] = useState(false)

  const selectedTicket = useMemo(() => tickets.find((ticket) => ticket.id === selectedId) ?? null, [selectedId, tickets])

  const loadTickets = async () => {
    setLoading(true)
    const { data } = await supabase.from("support_tickets").select("*").order("updated_at", { ascending: false })
    const next = (data as SupportTicket[]) ?? []
    setTickets(next)
    setSelectedId((current) => current ?? next[0]?.id ?? null)
    setLoading(false)
  }

  const loadMessages = async (ticketId: string | null) => {
    if (!ticketId) {
      setMessages([])
      return
    }
    const { data } = await supabase
      .from("support_messages")
      .select("*")
      .eq("ticket_id", ticketId)
      .order("created_at", { ascending: true })
    setMessages((data as SupportMessage[]) ?? [])
  }

  useEffect(() => { void loadTickets() }, [])
  useEffect(() => { void loadMessages(selectedId) }, [selectedId])

  const createTicket = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!userId || !subject.trim() || !newMessage.trim()) {
      toast.error("Inserisci oggetto e messaggio")
      return
    }
    setSubmitting(true)
    const { data: ticket, error } = await supabase
      .from("support_tickets")
      .insert({ user_id: userId, subject: subject.trim() })
      .select("*")
      .single()
    if (error || !ticket) {
      setSubmitting(false)
      toast.error(error?.message || "Ticket non creato")
      return
    }
    const created = ticket as SupportTicket
    const { error: msgError } = await supabase.from("support_messages").insert({
      ticket_id: created.id,
      sender_id: userId,
      sender_role: "user",
      message: newMessage.trim(),
    })
    setSubmitting(false)
    if (msgError) {
      toast.error(msgError.message)
      return
    }
    setSubject("")
    setNewMessage("")
    setSelectedId(created.id)
    toast.success("Ticket aperto")
    void loadTickets()
  }

  const sendReply = async () => {
    if (!userId || !selectedTicket) return
    if (!reply.trim()) {
      toast.error("Il messaggio non puo essere vuoto")
      return
    }
    setSubmitting(true)
    const { error } = await supabase.from("support_messages").insert({
      ticket_id: selectedTicket.id,
      sender_id: userId,
      sender_role: "user",
      message: reply.trim(),
    })
    setSubmitting(false)
    if (error) {
      toast.error(error.message)
      return
    }
    setReply("")
    void loadMessages(selectedTicket.id)
    void loadTickets()
  }

  const closeTicket = async () => {
    if (!selectedTicket) return
    setClosing(true)
    const { error } = await supabase.rpc("support_ticket_close", { p_ticket_id: selectedTicket.id })
    setClosing(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Ticket chiuso")
    void loadTickets()
    void loadMessages(selectedTicket.id)
  }

  return (
    <AppShell title="Supporto">
      <TonalCard className="mb-4">
        <div className="flex items-start gap-3">
          <div className="flex size-12 items-center justify-center rounded-2xl bg-[var(--surface-low)]">
            <Headphones className="size-5 text-[var(--primary)]" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="font-bold">Servizio clienti</p>
            <p className="mt-0.5 text-sm text-[var(--muted-foreground)]">Apri un ticket o continua una conversazione esistente.</p>
          </div>
          <Button type="button" variant="ghost" size="icon-sm" onClick={() => { void loadTickets(); void loadMessages(selectedId) }} className="rounded-full bg-[var(--surface-high)] text-[var(--primary)]">
            <RefreshCw className="size-4" />
          </Button>
        </div>
      </TonalCard>

      <TonalCard className="mb-4">
        <form onSubmit={createTicket} className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Oggetto</Label>
            <Input value={subject} onChange={(e) => setSubject(e.target.value)} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="Es. Problema con prenotazione" />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label className="label-sm text-[var(--muted-foreground)]">Messaggio</Label>
            <Textarea value={newMessage} onChange={(e) => setNewMessage(e.target.value)} rows={4} className="rounded-2xl bg-[var(--surface-low)] border-0 resize-none" placeholder="Descrivi la richiesta..." />
          </div>
          <Button type="submit" disabled={submitting} className="h-12 rounded-2xl btn-primary-grad font-bold">
            {submitting ? <Spinner /> : (<><Send className="size-4" /> Apri ticket</>)}
          </Button>
        </form>
      </TonalCard>

      <div className="mb-3 px-1">
        <h2 className="text-lg font-bold">Ticket</h2>
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : tickets.length === 0 ? (
        <TonalCard className="py-8 text-center">
          <p className="text-sm text-[var(--muted-foreground)]">Nessun ticket aperto.</p>
        </TonalCard>
      ) : (
        <div className="flex flex-col gap-3">
          {tickets.map((ticket) => (
            <TonalCard key={ticket.id} active={ticket.id === selectedId} onClick={() => setSelectedId(ticket.id)}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-bold">{ticket.subject}</p>
                  <p className="mt-1 text-xs text-[var(--muted-foreground)]">{new Date(ticket.updated_at).toLocaleString("it-IT")}</p>
                </div>
                <StatusChip status={ticket.status} />
              </div>
            </TonalCard>
          ))}
        </div>
      )}

      {selectedTicket && (
        <TonalCard className="mt-4">
          <div className="mb-4 flex items-center justify-between gap-3">
            <div>
              <p className="label-sm text-[var(--muted-foreground)]">CONVERSAZIONE</p>
              <h2 className="mt-1 text-lg font-bold">{selectedTicket.subject}</h2>
            </div>
            <div className="flex items-center gap-2">
              <StatusChip status={selectedTicket.status} />
              {selectedTicket.status !== "closed" && (
                <Button type="button" variant="ghost" size="sm" onClick={closeTicket} disabled={closing} className="rounded-xl bg-[var(--secondary-container)] text-[var(--secondary-foreground)]">
                  {closing ? <Spinner /> : (<><CheckCircle2 className="size-4" /> Chiudi</>)}
                </Button>
              )}
            </div>
          </div>

          <div className="flex max-h-80 flex-col gap-2 overflow-y-auto rounded-2xl bg-[var(--surface-low)] p-3">
            {messages.map((message) => (
              <div key={message.id} className={message.sender_role === "user" ? "ml-8 rounded-2xl bg-white p-3" : "mr-8 rounded-2xl bg-[var(--surface-high)] p-3"}>
                <p className="text-sm font-semibold">{message.message}</p>
                <p className="mt-1 text-[0.6875rem] text-[var(--muted-foreground)]">{message.sender_role === "user" ? "Tu" : "Operatore"} - {new Date(message.created_at).toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit" })}</p>
              </div>
            ))}
          </div>

          <div className="mt-3 flex gap-2">
            <Input value={reply} onChange={(e) => setReply(e.target.value)} disabled={selectedTicket.status === "closed"} className="h-12 rounded-2xl bg-[var(--surface-low)] border-0" placeholder="Scrivi un messaggio..." />
            <Button onClick={sendReply} disabled={submitting || selectedTicket.status === "closed"} className="h-12 rounded-2xl btn-primary-grad px-4">
              {submitting ? <Spinner /> : <Send className="size-4" />}
            </Button>
          </div>
        </TonalCard>
      )}

      <Button asChild variant="ghost" className="mt-5 h-12 w-full rounded-2xl bg-[var(--surface-high)] font-bold text-[var(--primary)]">
        <Link to="/report"><TriangleAlert className="size-5" /> Segnala un mezzo</Link>
      </Button>
    </AppShell>
  )
}
