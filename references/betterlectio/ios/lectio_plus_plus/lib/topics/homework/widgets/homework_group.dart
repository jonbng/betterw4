import 'package:flutter/material.dart';
import 'package:lectio_wrapper/lectio_wrapper.dart';
import 'package:lpp/topics/homework/widgets/homework_item.dart';
import 'package:lpp/utils/helpers.dart';
import 'package:lpp/widgets/layout/text_divider.dart';

class HomeworkGroup extends StatelessWidget {
  const HomeworkGroup({super.key, required this.homework, required this.time});
  final List<Homework> homework;
  final DateTime time;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextDivider(
          text: formatDateReadable(time),
          primary: true,
        ),
        ...homework.map((e) => HomeworkItem(homework: e))
      ],
    );
  }
}
