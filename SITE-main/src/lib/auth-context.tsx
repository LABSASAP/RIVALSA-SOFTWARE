import { createContext, useContext, useEffect, useState, type ReactNode } from "react"
import type { Session } from "@supabase/supabase-js"
import { supabase, type Profile } from "@/lib/supabase"

type AuthState = {
  session: Session | null
  profile: Profile | null
  loading: boolean
  signOut: () => Promise<void>
  refreshProfile: () => Promise<void>
}

const AuthContext = createContext<AuthState | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  const loadProfile = async (userId: string) => {
    const { data } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", userId)
      .maybeSingle()
    return (data as Profile) ?? null
  }

  useEffect(() => {
    let active = true

    const syncAuthState = async (nextSession: Session | null) => {
      if (!active) return
      setLoading(true)
      setSession(nextSession)

      if (nextSession?.user) {
        const nextProfile = await loadProfile(nextSession.user.id)
        if (!active) return
        setProfile(nextProfile)
      } else {
        setProfile(null)
      }

      if (active) {
        setLoading(false)
      }
    }

    supabase.auth.getSession().then(({ data }) => {
      void syncAuthState(data.session)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      void syncAuthState(s)
    })

    return () => {
      active = false
      sub.subscription.unsubscribe()
    }
  }, [])

  const signOut = async () => {
    await supabase.auth.signOut()
    setProfile(null)
  }

  const refreshProfile = async () => {
    if (session?.user) {
      const nextProfile = await loadProfile(session.user.id)
      setProfile(nextProfile)
    }
  }

  return (
    <AuthContext.Provider value={{ session, profile, loading, signOut, refreshProfile }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error("useAuth must be used within AuthProvider")
  return ctx
}
