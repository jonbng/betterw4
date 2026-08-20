import { Code, EyeOff, GraduationCap, Heart, Shield } from "@/components/site/icons"
import { siteContainerClass } from "@/components/site/styles"
import { cn } from "@/lib/utils"

const ITEMS = [
  { icon: <Heart />, label: "Free" },
  { icon: <GraduationCap />, label: "Built by students" },
  { icon: <Code />, label: "Open source" },
  { icon: <EyeOff />, label: "No ads" },
  { icon: <Shield />, label: "No servers, no tracking" },
]

export function TrustBar() {
  return (
    <div className={cn(siteContainerClass, "pb-4")}>
      <ul className="flex flex-wrap items-center justify-center gap-x-7 gap-y-3 rounded-2xl border border-line bg-white/60 px-6 py-4 backdrop-blur-sm">
        {ITEMS.map((item) => (
          <li
            key={item.label}
            className="inline-flex items-center gap-2 text-sm font-semibold text-ink-muted [&_svg]:size-[18px] [&_svg]:text-ink"
          >
            {item.icon}
            {item.label}
          </li>
        ))}
      </ul>
    </div>
  )
}
