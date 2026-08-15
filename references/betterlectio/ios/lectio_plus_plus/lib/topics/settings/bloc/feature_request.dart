import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lectio_wrapper/utils/dio_client.dart';

class FeatureRequestBloc extends Cubit<FeatureRequestState> {
  FeatureRequestBloc() : super(FeatureRequestState("", "", false));

  setTopic(String topic) {
    emit(FeatureRequestState(topic, state.content, state.submitted));
  }

  setContent(String content) {
    emit(FeatureRequestState(state.topic, content, state.submitted));
  }

  sendRequest() async {
    await lppDio.post("https://lpp.oscarspalk.com/api/feature",
        data: {"topic": state.topic, "content": state.content});
  }

  submit() {
    sendRequest();
    emit(FeatureRequestState(state.topic, state.content, true));
  }
}

class FeatureRequestState {
  String topic;
  String content;
  bool submitted;
  bool valid;
  FeatureRequestState(this.topic, this.content, this.submitted)
      : valid = topic.isNotEmpty && content.length > 10;
}
