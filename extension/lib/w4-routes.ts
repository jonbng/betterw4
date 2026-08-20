/**
 * Student information architecture for W4, captured from a live student
 * account. The native `.sdmenu` only exists on the current section's pages,
 * so the sidebar uses this fixed map instead of snapshotting one menu.
 *
 * Source of truth for routes: PROTOCOL.md in the repo root.
 */

export interface W4NavLink {
  label: string;
  route: string;
  params?: Record<string, string>;
}

export interface W4NavSection {
  id: string;
  label: string;
  links: W4NavLink[];
}

export const PRIMARY_LINKS: W4NavLink[] = [
  { label: 'Home', route: 'site/index' },
  { label: 'Timetable', route: 'academics/timetable/mytimetable' },
  { label: 'Assessments', route: 'academics/deadlines' },
  { label: 'Mail', route: 'mailer/inbox' },
  { label: 'Documents', route: 'documents' },
];

export const NAV_SECTIONS: W4NavSection[] = [
  {
    id: 'academics',
    label: 'Academics',
    links: [
      { label: 'My assessments', route: 'academics/deadlines' },
      { label: 'My timetable', route: 'academics/timetable/mytimetable' },
      { label: 'My classes', route: 'academics/classes/myclasses' },
      { label: 'My teachers', route: 'people/students/staff', params: { type: 'teachers' } },
      { label: 'My absences', route: 'people/students/absences' },
      { label: 'Register absences', route: 'people/students/absences/register' },
      { label: 'My grades', route: 'academics/grades/grades' },
      { label: 'SAT/ACT scores', route: 'academics/grades/grades/sat' },
      { label: 'Transcripts', route: 'academics/transcripts/transcripts' },
      { label: 'Records of Progress', route: 'academics/rop' },
      { label: 'Extended Essay', route: 'academics/ee' },
      { label: 'Testimonial form', route: 'academics/testimonial' },
      { label: 'Personal feeds', route: 'academics/feeds' },
      { label: 'All classes', route: 'academics/classes/allclasses' },
      { label: 'All assessments', route: 'academics/classes/assessments/all' },
      { label: 'Subject pages', route: 'academics/subjects/pages' },
      { label: 'My trips', route: 'academics/trips' },
      { label: 'Travel forms', route: 'academics/travel/travel.list' },
      { label: 'Resource bookings', route: 'academics/resources/resources' },
    ],
  },
  {
    id: 'extra-academics',
    label: 'Extra Academics',
    links: [
      { label: 'EA timetable', route: 'extraacademics/timetable/mytimetable' },
      { label: 'My activities', route: 'extraacademics/activities/myactivities' },
      { label: 'Group leaders', route: 'people/students/staff', params: { type: 'leaders' } },
      { label: 'EA diary', route: 'extraacademics/activities/myactivities/diary' },
      { label: 'Portfolio', route: 'extraacademics/activities/myportfolio' },
      { label: 'EA absences', route: 'people/students/eaabsences' },
      { label: 'CAS interviews', route: 'extraacademics/activities/interviews' },
      { label: 'SafetyNet', route: 'extraacademics/safetynet/mysafetynet' },
      { label: 'All activities', route: 'extraacademics/activities/ea' },
    ],
  },
  {
    id: 'school',
    label: 'School',
    links: [
      { label: 'Teachers / leaders', route: 'people/students/staff' },
      { label: 'Letter of Attendance', route: 'people/students/letter/attendance' },
      { label: 'All students', route: 'people/students/all' },
      { label: 'By house', route: 'people/students/byhouse' },
      { label: 'Current staff', route: 'people/staff/current' },
      { label: 'Birthdays', route: 'people/birthdays' },
      { label: 'Rooms', route: 'academics/timetable/room' },
      { label: "Who's on duty", route: 'people/onduty' },
      { label: 'Inbox', route: 'mailer/inbox' },
      { label: 'Compose', route: 'mailer/send', params: { type: 'freeform' } },
    ],
  },
];

export const ACCOUNT_LINKS: W4NavLink[] = [
  { label: 'Profile', route: 'site/profile' },
  { label: 'Password', route: 'site/password' },
  { label: 'Logout', route: 'site/logout' },
];
