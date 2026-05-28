import { useEffect, useState } from "react"
import { toast } from "sonner"
import { ArrowDownToLine, Coins, Gift } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type CreditTransaction, type CreditWallet } from "@/lib/supabase"

function normalizeWallet(data: unknown) {
  return (Array.isArray(data) ? data[0] : data) as CreditWallet | null
}

function formatCreditAmount(value: number | null | undefined) {
  return `${Number(value ?? 0).toFixed(2)} EUR`
}

function transactionValue(tx: CreditTransaction) {
  if (tx.type === "earned") return `+${tx.points} punti`
  const amount = Number(tx.amount ?? 0)
  if (amount > 0) return `-${formatCreditAmount(amount)}`
  return `-${tx.points} punti`
}

export function CreditsPage() {
  const [wallet, setWallet] = useState<CreditWallet | null>(null)
  const [transactions, setTransactions] = useState<CreditTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [redeeming, setRedeeming] = useState(false)

  const load = async () => {
    setLoading(true)
    const [{ data: walletData, error }, { data: txData }] = await Promise.all([
      supabase.rpc("credit_wallet_get"),
      supabase.from("credit_transactions").select("*").order("created_at", { ascending: false }).limit(20),
    ])
    if (error) {
      toast.error(error.message)
      setLoading(false)
      return
    }
    setWallet(normalizeWallet(walletData))
    setTransactions((txData as CreditTransaction[]) ?? [])
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const redeem = async () => {
    setRedeeming(true)
    const { data, error } = await supabase.rpc("credit_redeem", { p_points: 10 })
    setRedeeming(false)
    if (error) {
      toast.error(error.message)
      return
    }
    setWallet(normalizeWallet(data))
    toast.success("10 punti convertiti in credito")
    void load()
  }

  return (
    <AppShell title="Crediti">
      {loading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : (
        <>
          <TonalCard className="text-center">
            <div className="mx-auto flex size-14 items-center justify-center rounded-3xl btn-primary-grad">
              <Gift className="size-7 text-white" />
            </div>
            <p className="label-sm mt-4 text-[var(--muted-foreground)]">PROMOZIONI</p>
            <p className="mt-2 font-display text-5xl font-extrabold tabular-nums">{wallet?.points_balance ?? 0}</p>
            <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">punti disponibili</p>
          </TonalCard>

          <div className="mt-4 grid grid-cols-2 gap-3">
            <TonalCard>
              <p className="label-sm text-[var(--muted-foreground)]">CREDITO</p>
              <p className="mt-2 text-2xl font-extrabold">{formatCreditAmount(Number(wallet?.credit_amount ?? 0))}</p>
            </TonalCard>
            <TonalCard>
              <p className="label-sm text-[var(--muted-foreground)]">CONVERSIONE</p>
              <p className="mt-2 text-sm font-bold text-[var(--primary)]">10 punti = 1.00 EUR</p>
            </TonalCard>
          </div>

          <Button
            onClick={redeem}
            disabled={redeeming || (wallet?.points_balance ?? 0) < 10}
            className="mt-5 h-12 w-full rounded-2xl btn-primary-grad font-bold"
          >
            {redeeming ? <Spinner /> : (<><ArrowDownToLine className="size-5" /> Converti 10 punti</>)}
          </Button>

          <div className="mt-7 mb-3 px-1">
            <h2 className="text-lg font-bold">Movimenti</h2>
            <p className="text-sm text-[var(--muted-foreground)]">I punti vengono assegnati a fine corsa.</p>
          </div>

          {transactions.length === 0 ? (
            <TonalCard className="py-8 text-center">
              <Coins className="mx-auto size-7 text-[var(--muted-foreground)]" />
              <p className="mt-2 text-sm text-[var(--muted-foreground)]">Nessun movimento registrato.</p>
            </TonalCard>
          ) : (
            <div className="flex flex-col gap-3">
              {transactions.map((tx) => (
                <TonalCard key={tx.id}>
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="font-bold">{tx.description || (tx.type === "earned" ? "Punti guadagnati" : "Credito riscattato")}</p>
                      <p className="mt-1 text-xs text-[var(--muted-foreground)]">
                        {new Date(tx.created_at).toLocaleString("it-IT")}
                      </p>
                    </div>
                    <div className="text-right">
                      <p className={tx.type === "earned" ? "font-bold text-[var(--secondary)]" : "font-bold text-[var(--primary)]"}>
                        {transactionValue(tx)}
                      </p>
                      {tx.type === "earned" && Number(tx.amount) > 0 && (
                        <p className="text-xs font-semibold text-[var(--muted-foreground)]">{formatCreditAmount(Number(tx.amount))}</p>
                      )}
                    </div>
                  </div>
                </TonalCard>
              ))}
            </div>
          )}
        </>
      )}
    </AppShell>
  )
}
