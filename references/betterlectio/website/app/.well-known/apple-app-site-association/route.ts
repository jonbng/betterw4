const association = {
  applinks: {
    apps: [],
    details: [
      {
        appIDs: ["9ULRK8DH95.dk.echolabs.betterlectio.app"],
        components: [{ "/": "/r/*", comment: "BetterLectio referral links" }],
      },
    ],
  },
  appclips: {
    apps: ["9ULRK8DH95.dk.echolabs.betterlectio.app.Clip"],
  },
}

export function GET() {
  return Response.json(association, {
    headers: { "Cache-Control": "public, max-age=3600" },
  })
}
