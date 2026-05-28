import { useEffect, useMemo, useState } from "react"
import { toast } from "sonner"
import { Send } from "lucide-react"
import { StatusChip, TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type OperatorSupportTicket, type SupportMessage, type SupportTicket } from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

export function OperatorSupportPage() {
  const [tickets, setTickets] = useState<OperatorSupportTicket[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [messages, setMessages] = useState<SupportMessage[]>([])
  const [reply, setReply] = useState("")
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)

  const selectedTicket = useMemo(() => tickets.find((ticket) => ticket.id === selectedId) ?? null, [selectedId, tickets])

  const loadTickets = async () => {
    setLoading(true)
    const { data } = await supabase.rpc("operator_support_tickets")
    const rows = ((data as OperatorSupportTicket[] | null) ?? []).map((ticket) => ({
      ...ticket,
      message_count: Number(ticket.message_count ?? 0),
    }))
    setTickets(rows)
    setSelectedId((current) => current ?? rows[0]?.id ?? null)
    setLoading(false)
  }

  const loadMessages = async (ticketId: string | null) => {
    if (!ticketId) {
      setMessages([])
      return
    }
    const { data } = await supabase.rpc("operator_support_messages", { p_ticket_id: ticketId })
    setMessages((data as SupportMessage[]) ?? [])
  }

  useEffect(() => { void loadTickets() }, [])
  useEffect(() => { void loadMessages(selectedId) }, [selectedId])

  const updateStatus = async (status: SupportTicket["status"]) => {
    if (!selectedTicket) return
    const { error } = await supabase.rpc("operator_support_update_status", {
      p_ticket_id: selectedTicket.id,
      p_status: status,
    })
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Ticket aggiornato")
    void loadTickets()
  }

  const sendReply = async () => {
    if (!selectedTicket) return
    if (selectedTicket.status === "closed") {
      toast.error("Il ticket e chiuso")
      return
    }
    if (!reply.trim()) {
      toast.error("Il messaggio non puo essere vuoto")
      return
    }
    setSending(true)
    const { error } = await supabase.rpc("operator_support_send_message", {
      p_ticket_id: selectedTicket.id,
      p_message: reply.trim(),
    })
    setSending(false)
    if (error) {
      toast.error(error.message)
      return
    }
    setReply("")
    void loadMessages(selectedTicket.id)
    void loadTickets()
  }

  const counts = {
    open: tickets.filter((ticket) => ticket.status === "open").length,
    progress: tickets.filter((ticket) => ticket.status === "in_progress").length,
    resolved: tickets.filter((ticket) => ticket.status === "resolved").length,
  }

  return (
    <>
      <PageHeader title="Supporto clienti" subtitle="Gestisci ticket e conversazioni con gli utenti." />
      <PageBody>
        <div className="mb-6 grid grid-cols-3 gap-4">
          <StatCard label="APERTI" value={counts.open} tone="danger" />
          <StatCard label="IN LAVORAZIONE" value={counts.progress} tone="warning" />
          <StatCard label="RISOLTI" value={counts.resolved} tone="primary" />
        </div>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : (
          <div className="grid gap-5 lg:grid-cols-[380px_1fr]">
            <div className="flex flex-col gap-3">
              {tickets.length === 0 ? (
                <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Nessun ticket.</TonalCard>
              ) : tickets.map((ticket) => (
                <TonalCard key={ticket.id} active={ticket.id === selectedId} onClick={() => setSelectedId(ticket.id)}>
                  <div className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <p className="font-bold">{ticket.subject}</p>
                      <p className="mt-1 truncate text-sm text-[var(--muted-foreground)]">{ticket.user_name} - {ticket.user_email}</p>
                      <p className="mt-1 text-xs font-semibold text-[var(--muted-foreground)]">{ticket.message_count} messaggi</p>
                    </div>
                    <StatusChip status={ticket.status} />
                  </div>
                </TonalCard>
              ))}
            </div>

            {selectedTicket && (
              <TonalCard>
                <div className="mb-4 flex items-start justify-between gap-4">
                  <div>
                    <p className="label-sm text-[var(--muted-foreground)]">TICKET</p>
                    <h2 className="mt-1 text-2xl font-extrabold">{selectedTicket.subject}</h2>
                    <p className="mt-1 text-sm text-[var(--muted-foreground)]">{selectedTicket.user_name} - {selectedTicket.user_email}</p>
                  </div>
                  <Select value={selectedTicket.status} onValueChange={(value) => updateStatus(value as SupportTicket["status"])}>
                    <SelectTrigger className="h-11 w-44 rounded-2xl border-0 bg-[var(--surface-low)]">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="open">Aperto</SelectItem>
                      <SelectItem value="in_progress">In lavorazione</SelectItem>
                      <SelectItem value="resolved">Risolto</SelectItem>
                      <SelectItem value="closed">Chiuso</SelectItem>
                    </SelectContent>
                  </Select>
                </div>

                <div className="flex max-h-[420px] flex-col gap-2 overflow-y-auto rounded-2xl bg-[var(--surface-low)] p-4">
                  {messages.map((message) => (
                    <div key={message.id} className={message.sender_role === "operator" ? "ml-20 rounded-2xl bg-white p-3" : "mr-20 rounded-2xl bg-[var(--surface-high)] p-3"}>
                      <p className="text-sm font-semibold">{message.message}</p>
                      <p className="mt-1 text-[0.6875rem] text-[var(--muted-foreground)]">
                        {message.sender_role === "operator" ? "Operatore" : "Utente"} - {new Date(message.created_at).toLocaleString("it-IT")}
                      </p>
                    </div>
                  ))}
                </div>

                <div className="mt-4 flex gap-3">
                  <Input
                    value={reply}
                    onChange={(event) => setReply(event.target.value)}
                    disabled={selectedTicket.status === "closed"}
                    className="h-12 rounded-2xl border-0 bg-[var(--surface-low)]"
                    placeholder={selectedTicket.status === "closed" ? "Ticket chiuso" : "Rispondi al ticket..."}
                  />
                  <Button onClick={sendReply} disabled={sending || selectedTicket.status === "closed"} className="h-12 rounded-2xl btn-primary-grad px-5 font-bold">
                    {sending ? <Spinner /> : (<><Send className="size-4" /> Invia</>)}
                  </Button>
                </div>
              </TonalCard>
            )}
          </div>
        )}
      </PageBody>
    </>
  )
}
