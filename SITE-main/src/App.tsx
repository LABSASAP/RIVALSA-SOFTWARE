import { Navigate, Route, Routes } from "react-router-dom"
import { useAuth } from "@/lib/auth-context"
import { LoginPage } from "@/pages/login"
import { NearbyPage } from "@/pages/nearby"
import { VehicleDetailPage } from "@/pages/vehicle-detail"
import { ReservationPage } from "@/pages/reservation"
import { RidePage } from "@/pages/ride"
import { RideSummaryPage } from "@/pages/ride-summary"
import { PaymentMethodsPage } from "@/pages/payment-methods"
import { ReportVehiclePage } from "@/pages/report-vehicle"
import { OperatorLayout } from "@/pages/operator/layout"
import { OperatorReportsPage } from "@/pages/operator/reports"
import { OperatorReservationsPage } from "@/pages/operator/reservations"
import { OperatorEndLocationPage } from "@/pages/operator/end-location"
import { OperatorUsersPage } from "@/pages/operator/users"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"

function Splash() {
  return (
    <div className="app-shell flex flex-col items-center justify-center min-h-svh gap-4">
      <div className="size-20 rounded-3xl btn-primary-grad flex items-center justify-center font-display text-4xl font-extrabold shadow-[0_16px_40px_rgba(0,64,161,0.25)]">
        Z
      </div>
      <div className="text-center">
        <p className="label-sm text-[var(--muted-foreground)]">URBAN MOBILITY</p>
        <h1 className="text-3xl font-extrabold tracking-tight mt-0.5">ZooSmart</h1>
      </div>
      <Spinner />
    </div>
  )
}

function SetupRequired() {
  const { signOut } = useAuth()

  return (
    <div className="app-shell flex flex-col items-center justify-center min-h-svh px-6">
      <div className="max-w-sm w-full rounded-3xl bg-[var(--surface-lowest)] p-6 shadow-[0_12px_32px_rgba(25,28,29,0.04)]">
        <p className="label-sm text-[var(--muted-foreground)]">SUPABASE SETUP</p>
        <h1 className="text-2xl font-extrabold tracking-tight mt-1">Profilo utente mancante</h1>
        <p className="text-sm text-[var(--muted-foreground)] mt-3 leading-relaxed">
          L&apos;accesso Auth esiste, ma nel database manca la riga corrispondente in <span className="font-mono">profiles</span>.
        </p>
        <div className="mt-4 rounded-2xl bg-[var(--surface-low)] p-4 text-sm text-[var(--muted-foreground)] leading-relaxed">
          Esegui la migration <span className="font-mono">20260515170000_zoosmart_local_bootstrap.sql</span>, poi esci e rientra.
        </div>
        <Button
          onClick={async () => {
            await signOut()
          }}
          className="mt-5 h-12 w-full rounded-2xl btn-primary-grad font-bold"
        >
          Esci e riprova
        </Button>
      </div>
    </div>
  )
}

function Protected({ children, role }: { children: React.ReactNode; role?: "user" | "operator" }) {
  const { session, profile, loading } = useAuth()
  if (loading) return <Splash />
  if (!session) return <Navigate to="/login" replace />
  if (!profile) return <SetupRequired />
  if (role && profile?.role !== role) {
    return <Navigate to={profile?.role === "operator" ? "/operator" : "/"} replace />
  }
  return <>{children}</>
}

function RootRedirect() {
  const { session, profile, loading } = useAuth()
  if (loading) return <Splash />
  if (!session) return <Navigate to="/login" replace />
  if (!profile) return <SetupRequired />
  if (profile?.role === "operator") return <Navigate to="/operator" replace />
  return <Navigate to="/nearby" replace />
}

export function App() {
  return (
    <Routes>
      <Route path="/" element={<RootRedirect />} />
      <Route path="/login" element={<LoginPage />} />

      <Route path="/nearby" element={<Protected role="user"><NearbyPage /></Protected>} />
      <Route path="/vehicles/:id" element={<Protected role="user"><VehicleDetailPage /></Protected>} />
      <Route path="/reservation" element={<Protected role="user"><ReservationPage /></Protected>} />
      <Route path="/ride" element={<Protected role="user"><RidePage /></Protected>} />
      <Route path="/ride/:id/summary" element={<Protected role="user"><RideSummaryPage /></Protected>} />
      <Route path="/payment-methods" element={<Protected role="user"><PaymentMethodsPage /></Protected>} />
      <Route path="/report" element={<Protected role="user"><ReportVehiclePage /></Protected>} />

      <Route path="/operator" element={<Protected role="operator"><OperatorLayout /></Protected>}>
        <Route index element={<OperatorReportsPage />} />
        <Route path="reservations" element={<OperatorReservationsPage />} />
        <Route path="end-location" element={<OperatorEndLocationPage />} />
        <Route path="users" element={<OperatorUsersPage />} />
      </Route>

      <Route path="*" element={<RootRedirect />} />
    </Routes>
  )
}

export default App
