import type { ReactNode } from "react"
import { Link, useLocation, useNavigate } from "react-router-dom"
import { ArrowLeft, CreditCard, Hop as Home, LogOut, MapPin, TriangleAlert } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuth } from "@/lib/auth-context"
import { cn } from "@/lib/utils"

export function AppShell({
  title,
  children,
  back,
  hideTabs,
}: {
  title?: string
  children: ReactNode
  back?: string | true
  hideTabs?: boolean
}) {
  const navigate = useNavigate()
  const { signOut } = useAuth()
  const { pathname } = useLocation()

  return (
    <div className="app-shell flex flex-col">
      <header className="glass-header px-5 py-4 flex items-center gap-3">
        {back ? (
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={() => (typeof back === "string" ? navigate(back) : navigate(-1))}
            className="rounded-full bg-[var(--surface-high)] hover:bg-[var(--surface-low)]"
          >
            <ArrowLeft />
          </Button>
        ) : (
          <div className="flex items-center gap-2">
            <div className="size-9 rounded-2xl btn-primary-grad flex items-center justify-center font-display font-bold">
              Z
            </div>
          </div>
        )}
        <div className="flex-1">
          <p className="label-sm text-[var(--muted-foreground)]">ZooSmart</p>
          {title && <h1 className="text-xl font-bold tracking-tight">{title}</h1>}
        </div>
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={async () => {
            await signOut()
            navigate("/login")
          }}
          className="rounded-full bg-[var(--surface-high)] hover:bg-[var(--surface-low)]"
        >
          <LogOut />
        </Button>
      </header>

      <main className="flex-1 px-5 pt-4 pb-28">{children}</main>

      {!hideTabs && (
        <nav className="fixed bottom-3 left-1/2 -translate-x-1/2 w-[calc(100%-1.5rem)] max-w-[calc(430px-1.5rem)] z-30">
          <div className="rounded-3xl bg-white shadow-[0_12px_32px_rgba(25,28,29,0.08)] grid grid-cols-3 p-1.5">
            <TabLink to="/nearby" icon={<Home className="size-5" />} label="Mezzi" active={pathname.startsWith("/nearby") || pathname.startsWith("/vehicles") || pathname.startsWith("/reservation") || pathname.startsWith("/ride")} />
            <TabLink to="/payment-methods" icon={<CreditCard className="size-5" />} label="Pagamenti" active={pathname.startsWith("/payment-methods")} />
            <TabLink to="/report" icon={<TriangleAlert className="size-5" />} label="Segnala" active={pathname.startsWith("/report")} />
          </div>
        </nav>
      )}
    </div>
  )
}

function TabLink({
  to,
  icon,
  label,
  active,
}: {
  to: string
  icon: ReactNode
  label: string
  active: boolean
}) {
  return (
    <Link
      to={to}
      className={cn(
        "flex flex-col items-center justify-center gap-0.5 py-2 rounded-2xl transition-colors",
        active
          ? "bg-[var(--surface-low)] text-[var(--primary)]"
          : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
      )}
    >
      {icon}
      <span className="text-[0.6875rem] font-semibold">{label}</span>
    </Link>
  )
}

export function VehicleIcon({ type, className }: { type: "bike" | "scooter" | "car"; className?: string }) {
  const map: Record<string, string> = { bike: "🚲", scooter: "🛴", car: "🚗" }
  return (
    <span className={cn("inline-flex items-center justify-center text-2xl", className)} aria-hidden>
      <MapPin className="hidden" />
      {map[type]}
    </span>
  )
}
