import 'package:flutter/material.dart';
import 'package:lectio_wrapper/types/class.dart';
import 'package:lpp/logic/student/student_cubit.dart';
import 'package:lpp/topics/classes/widgets/class_list_item.dart';
import 'package:lpp/topics/state/empty.dart';
import 'package:lpp/widgets/loading/student_bloc_builder.dart';

class ClassesOverviewScreen extends StatelessWidget {
  const ClassesOverviewScreen({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return StudentBlocBuilder<StudentCubit<List<ClassRef>>, List<ClassRef>?>(
      builder: (context, state) {
        List<ClassRef> classes = state!;
        if (classes.isEmpty) {
          return const EmptyScreen();
        }
        return GridView.builder(
          padding: const EdgeInsets.all(6.0),
          itemCount: classes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              childAspectRatio: 16.0 / 12.0, crossAxisCount: 2),
          itemBuilder: (context, index) {
            return ClassListItem(klasse: classes.elementAt(index));
          },
        );
      },
    );
  }
}
