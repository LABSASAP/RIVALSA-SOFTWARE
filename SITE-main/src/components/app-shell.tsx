import type { ReactNode } from "react"
import { Link, useLocation, useNavigate } from "react-router-dom"
import { ArrowLeft, CreditCard, Gift, Headphones, Home, LogOut, MapPin, UserRound } from "lucide-react"
import { Button } from "@/components/ui/button"
import { useAuth } from "@/lib/auth-context"
import { cn } from "@/lib/utils"

export function AppShell({
  title,
  children,
  back,
  hideTabs,
  variant = "default",
  mainClassName,
}: {
  title?: string
  children: ReactNode
  back?: string | true
  hideTabs?: boolean
  variant?: "default" | "wide"
  mainClassName?: string
}) {
  const navigate = useNavigate()
  const { signOut } = useAuth()
  const { pathname } = useLocation()
  const rideSectionActive =
    pathname.startsWith("/nearby") ||
    pathname.startsWith("/vehicles") ||
    pathname.startsWith("/reservation") ||
    pathname.startsWith("/ride")
  const paymentSectionActive = pathname.startsWith("/payment-methods")
  const creditsSectionActive = pathname.startsWith("/credits")
  const supportSectionActive = pathname.startsWith("/support")
  const profileSectionActive = pathname.startsWith("/profile")

  return (
    <div className={cn("app-shell flex flex-col", variant === "wide" && "app-shell-wide")}>
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
        <div className="min-w-0 flex-1">
          <p className="label-sm text-[var(--muted-foreground)]">ZooSmart</p>
          {title && <h1 className="truncate text-xl font-bold tracking-tight">{title}</h1>}
        </div>

        {variant === "wide" && !hideTabs && (
          <nav className="hidden md:flex items-center gap-1 rounded-full bg-white/70 p-1 shadow-[0_12px_32px_rgba(25,28,29,0.06)] backdrop-blur-[20px]" aria-label="Navigazione utente">
            <DesktopNavLink to="/nearby" icon={<Home className="size-4" />} label="Mezzi" active={rideSectionActive} />
            <DesktopNavLink to="/payment-methods" icon={<CreditCard className="size-4" />} label="Pagamenti" active={paymentSectionActive} />
            <DesktopNavLink to="/credits" icon={<Gift className="size-4" />} label="Crediti" active={creditsSectionActive} />
            <DesktopNavLink to="/support" icon={<Headphones className="size-4" />} label="Supporto" active={supportSectionActive} />
            <DesktopNavLink to="/profile" icon={<UserRound className="size-4" />} label="Profilo" active={profileSectionActive} />
          </nav>
        )}

        <Button
          variant="ghost"
          size="icon-sm"
          aria-label="Logout"
          onClick={async () => {
            await signOut()
            navigate("/login")
          }}
          className={cn(
            "rounded-full bg-[var(--surface-high)] hover:bg-[var(--surface-low)]",
            variant === "wide" && "md:h-10 md:w-auto md:px-4 md:gap-2"
          )}
        >
          <LogOut className="size-5" />
          <span className={cn("sr-only", variant === "wide" && "md:not-sr-only md:text-sm md:font-bold")}>Logout</span>
        </Button>
      </header>

      <main className={cn("flex-1 px-5 pt-4 pb-28", variant === "wide" && "app-shell-main-wide", mainClassName)}>
        {children}
      </main>

      {!hideTabs && (
        <nav className={cn("fixed bottom-3 left-1/2 -translate-x-1/2 w-[calc(100%-1.5rem)] max-w-[calc(430px-1.5rem)] z-30", variant === "wide" && "app-shell-tabs-wide")}>
          <div className="grid grid-cols-5 rounded-3xl bg-white p-1.5 shadow-[0_12px_32px_rgba(25,28,29,0.08)]">
            <TabLink to="/nearby" icon={<Home className="size-5" />} label="Mezzi" active={rideSectionActive} />
            <TabLink to="/payment-methods" icon={<CreditCard className="size-5" />} label="Pay" active={paymentSectionActive} />
            <TabLink to="/credits" icon={<Gift className="size-5" />} label="Crediti" active={creditsSectionActive} />
            <TabLink to="/support" icon={<Headphones className="size-5" />} label="Help" active={supportSectionActive || pathname.startsWith("/report")} />
            <TabLink to="/profile" icon={<UserRound className="size-5" />} label="Profilo" active={profileSectionActive} />
          </div>
        </nav>
      )}
    </div>
  )
}

function DesktopNavLink({
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
        "inline-flex h-10 items-center gap-2 rounded-full px-4 text-sm font-bold transition-colors",
        active
          ? "bg-[var(--surface-low)] text-[var(--primary)]"
          : "text-[var(--muted-foreground)] hover:bg-[var(--surface-low)] hover:text-[var(--foreground)]"
      )}
    >
      {icon}
      <span>{label}</span>
    </Link>
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
