/*
  # Fix ambiguous user_id in credit wallet RPCs

  credit_wallet_get() returns a table with an output column named user_id. In
  PL/pgSQL, an unqualified conflict target like ON CONFLICT (user_id) can be
  resolved ambiguously between the output parameter and the table column.
*/

CREATE OR REPLACE FUNCTION public.credit_wallet_get()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  points_balance integer,
  credit_amount numeric,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO public.user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT ON CONSTRAINT user_credit_wallets_user_id_key DO NOTHING;

  RETURN QUERY
  SELECT w.id, w.user_id, w.points_balance, w.credit_amount, w.created_at, w.updated_at
  FROM public.user_credit_wallets AS w
  WHERE w.user_id = v_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.credit_redeem(p_points integer)
RETURNS public.user_credit_wallets
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_wallet public.user_credit_wallets;
  v_amount numeric(10,2);
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_points IS NULL OR p_points < 10 THEN
    RAISE EXCEPTION 'minimum redeem is 10 points';
  END IF;

  INSERT INTO public.user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT ON CONSTRAINT user_credit_wallets_user_id_key DO NOTHING;

  SELECT w.* INTO v_wallet
  FROM public.user_credit_wallets AS w
  WHERE w.user_id = v_user
  FOR UPDATE;

  IF v_wallet.points_balance < p_points THEN
    RAISE EXCEPTION 'insufficient points';
  END IF;

  v_amount := ROUND((p_points::numeric / 10.0)::numeric, 2);

  UPDATE public.user_credit_wallets AS w
  SET points_balance = w.points_balance - p_points,
      credit_amount = w.credit_amount + v_amount,
      updated_at = now()
  WHERE w.user_id = v_user
  RETURNING w.id, w.user_id, w.points_balance, w.credit_amount, w.created_at, w.updated_at
  INTO v_wallet;

  INSERT INTO public.credit_transactions (user_id, type, points, amount, description)
  VALUES (v_user, 'redeemed', p_points, v_amount, 'Conversione punti in credito promozionale');

  RETURN v_wallet;
END;
$$;

REVOKE ALL ON FUNCTION public.credit_wallet_get() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.credit_wallet_get() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.credit_redeem(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.credit_redeem(integer) TO authenticated, service_role;
