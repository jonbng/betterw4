package dk.betterlectio.android.feature.supabase

/**
 * Back-compat facade used by repositories that previously talked to a raw REST client.
 * Prefer injecting the focused services (`SupabaseSchoolService`, etc.) for new code.
 */
@Deprecated(
    message = "Use focused Supabase*Service classes",
    replaceWith = ReplaceWith("SupabaseManager"),
)
typealias SupabaseRestClient = SupabaseManager
