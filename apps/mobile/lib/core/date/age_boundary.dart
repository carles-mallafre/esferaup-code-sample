DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime yearsBefore(DateTime value, int years) {
  final year = value.year - years;
  final lastDay = DateTime(year, value.month + 1, 0).day;
  return DateTime(year, value.month, value.day.clamp(1, lastDay));
}

int calendarAge(DateTime dob, DateTime today) {
  final beforeBirthday =
      today.month < dob.month ||
      (today.month == dob.month && today.day < dob.day);
  return today.year - dob.year - (beforeBirthday ? 1 : 0);
}

bool isAdultDob(DateTime dob, DateTime today) =>
    !dateOnly(dob).isAfter(dateOnly(today)) && calendarAge(dob, today) >= 18;

bool isChildDob(DateTime dob, DateTime today) =>
    !dateOnly(dob).isAfter(dateOnly(today)) && calendarAge(dob, today) < 18;
