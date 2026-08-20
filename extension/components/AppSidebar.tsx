import { useState } from 'preact/hooks';
import {
  BookOpen,
  Calendar,
  ChevronRight,
  ClipboardList,
  EyeOff,
  FileText,
  FolderOpen,
  Home,
  Inbox,
  LogOut,
  Mail,
  Moon,
  School,
  Settings,
  Sun,
  User,
} from 'lucide-react';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
  SidebarSeparator,
} from '@/components/ui/sidebar';
import { CampusStatusWidget } from '@/components/CampusStatusWidget';
import { armBypass } from '@/lib/bypass-redesigns';
import { clearLoginState, getCachedProfile } from '@/lib/profile-cache';
import { getSettings, updateSetting } from '@/lib/settings-storage';
import { currentRouteActive } from '@/lib/w4-navigation';
import { NAV_SECTIONS, PRIMARY_LINKS } from '@/lib/w4-routes';
import { w4Url } from '@/lib/w4-url';
import { toast } from 'sonner';

const PRIMARY_ICONS: Record<string, typeof Home> = {
  'site/index': Home,
  'academics/timetable/mytimetable': Calendar,
  'academics/deadlines': ClipboardList,
  'mailer/inbox': Inbox,
  documents: FolderOpen,
};

const SECTION_ICONS: Record<string, typeof BookOpen> = {
  academics: BookOpen,
  'extra-academics': FileText,
  school: School,
};

function getCachedWindowProfile() {
  return ((window as unknown as { __BW_CACHED_PROFILE__?: ReturnType<typeof getCachedProfile> })
    .__BW_CACHED_PROFILE__ ?? getCachedProfile());
}

export function AppSidebar() {
  const profile = getCachedWindowProfile();
  const [darkMode, setDarkMode] = useState(() => getSettings().visual.darkMode);

  const initials = (profile?.fullName ?? 'W4')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('');

  const toggleDark = () => {
    const next = !darkMode;
    setDarkMode(next);
    updateSetting('visual', 'darkMode', next);
    document.documentElement.classList.toggle('dark', next);
  };

  return (
    <Sidebar>
      <SidebarHeader>
        <div className="flex items-center gap-2 px-2 py-1.5">
          <img
            src={browser.runtime.getURL('/assets/logo.png')}
            alt=""
            className="size-7 rounded-md"
          />
          <div className="min-w-0">
            <div className="text-sm font-semibold leading-tight">BetterW4</div>
            <div className="text-xs text-muted-foreground truncate">UWC Red Cross Nordic</div>
          </div>
        </div>
        <CampusStatusWidget />
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>Today</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {PRIMARY_LINKS.map((link) => {
                const Icon = PRIMARY_ICONS[link.route] ?? Mail;
                const href = w4Url(link.route, link.params);
                return (
                  <SidebarMenuItem key={link.route}>
                    <SidebarMenuButton asChild isActive={currentRouteActive(link.route, link.params)}>
                      <a href={href}>
                        <Icon />
                        <span>{link.label}</span>
                      </a>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                );
              })}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>

        {NAV_SECTIONS.map((section) => {
          const Icon = SECTION_ICONS[section.id] ?? BookOpen;
          const openByDefault = section.links.some((link) =>
            currentRouteActive(link.route, link.params),
          );
          return (
            <SidebarGroup key={section.id}>
              <SidebarGroupContent>
                <SidebarMenu>
                  <Collapsible defaultOpen={openByDefault} className="group/collapsible">
                    <SidebarMenuItem>
                      <CollapsibleTrigger asChild>
                        <SidebarMenuButton>
                          <Icon />
                          <span>{section.label}</span>
                          <ChevronRight className="ml-auto size-4 transition-transform group-data-[state=open]/collapsible:rotate-90" />
                        </SidebarMenuButton>
                      </CollapsibleTrigger>
                      <CollapsibleContent>
                        <SidebarMenuSub>
                          {section.links.map((link) => (
                            <SidebarMenuSubItem key={`${link.route}:${JSON.stringify(link.params ?? {})}`}>
                              <SidebarMenuSubButton
                                asChild
                                isActive={currentRouteActive(link.route, link.params)}
                              >
                                <a href={w4Url(link.route, link.params)}>{link.label}</a>
                              </SidebarMenuSubButton>
                            </SidebarMenuSubItem>
                          ))}
                        </SidebarMenuSub>
                      </CollapsibleContent>
                    </SidebarMenuItem>
                  </Collapsible>
                </SidebarMenu>
              </SidebarGroupContent>
            </SidebarGroup>
          );
        })}
      </SidebarContent>

      <SidebarSeparator />

      <SidebarFooter>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton onClick={toggleDark}>
              {darkMode ? <Sun /> : <Moon />}
              <span>{darkMode ? 'Light mode' : 'Dark mode'}</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() => window.dispatchEvent(new CustomEvent('betterw4:openSettings'))}
            >
              <Settings />
              <span>Settings</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton asChild>
              <a href={w4Url('site/profile')}>
                <User />
                <span>Profile</span>
              </a>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() => {
                armBypass();
                toast.message('Showing original W4 for 5 minutes');
                window.location.reload();
              }}
            >
              <EyeOff />
              <span>Show original W4</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          <SidebarMenuItem>
            <SidebarMenuButton
              onClick={() => {
                clearLoginState();
                window.location.href = w4Url('site/logout');
              }}
            >
              <LogOut />
              <span>Log out</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>

        <div className="flex items-center gap-2 px-2 py-1.5">
          <Avatar className="size-8">
            {profile?.pictureUrl ? (
              <AvatarImage src={profile.pictureUrl} className="object-top" />
            ) : null}
            <AvatarFallback>{initials || 'W4'}</AvatarFallback>
          </Avatar>
          <div className="min-w-0">
            <div className="truncate text-sm font-medium">{profile?.fullName ?? 'Student'}</div>
            <div className="truncate text-xs text-muted-foreground">
              {profile?.uwcId ?? 'UWC RCN'}
            </div>
          </div>
        </div>
      </SidebarFooter>
    </Sidebar>
  );
}
