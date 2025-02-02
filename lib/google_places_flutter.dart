library google_places_flutter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/place_type.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:rxdart/subjects.dart';
import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

import 'DioErrorHandler.dart';

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  GooglePlaceAutoCompleteTextFieldState? stateController;
  InputDecoration inputDecoration;
  ItemClick? itemClick;
  GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  bool isLatLngRequired = true;

  TextStyle textStyle;
  String googleAPIKey;
  int debounceTime = 600;
  List<String>? countries = [];
  TextEditingController textEditingController = TextEditingController();
  ListItemBuilder? itemBuilder;
  Widget? seperatedBuilder;
  void clearData;
  bool isCrossBtnShown;
  bool showError;
  FocusNode? focusNode;
  PlaceType? placeType;
  String? language;
  Widget? suffixButton;
  String? Function(String?)? validator;
  final bool useOverlay;
  final EdgeInsetsGeometry listPadding;
  final ScrollPhysics? physics;

  GooglePlaceAutoCompleteTextField(
      {required this.textEditingController,
      required this.googleAPIKey,
        this.stateController,
      this.debounceTime: 600,
      this.inputDecoration: const InputDecoration(),
      this.itemClick,
      this.isLatLngRequired = true,
      this.textStyle: const TextStyle(),
      this.countries,
      this.getPlaceDetailWithLatLng,
      this.itemBuilder,
      this.isCrossBtnShown = true,
      this.seperatedBuilder,
      this.showError = true,
      this.focusNode,
      this.placeType,this.language='en',
      this.suffixButton,
        this.validator,
        this.useOverlay=true,
        this.listPadding= EdgeInsets.zero, this.physics,
      }){
    focusNode ??= FocusNode();
  }

  @override
  GooglePlaceAutoCompleteTextFieldState createState() =>
      GooglePlaceAutoCompleteTextFieldState();
}

class GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  TextEditingController controller = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  bool isSearched = false;

  bool isCrossBtn = true;
  late var _dio;

  CancelToken? _cancelToken = CancelToken();

  @override
  Widget build(BuildContext context) {

    var textFormField = TextFormField(
        decoration: widget.inputDecoration.copyWith(
          suffixIcon:(!widget.isCrossBtnShown)
              ? null
              : isCrossBtn && _showCrossIconWidget()
              ?widget.suffixButton!=null?
          InkWell(
            onTap: clearData,
            child: widget.suffixButton,
          )
              : IconButton(onPressed: clearData, icon: Icon(Icons.close))
              : null
        ),
        onTapOutside: (d){
          widget.focusNode?.unfocus();
        },
        style: widget.textStyle,
        controller: widget.textEditingController,
        focusNode: widget.focusNode,
        validator: widget.validator,
        onChanged: (string) {
          if(string.trim().isEmpty){
            clearData();
          }else {
            subject.add(string);
            if (widget.isCrossBtnShown) {
              isCrossBtn = string.isNotEmpty ? true : false;
              setState(() {});
            }
          }
        },
      );
    if(widget.useOverlay) {
      return CompositedTransformTarget(
        link: _layerLink,
        child: textFormField,
      );
    } else{
      return Column(
        children: [
          textFormField,
          buildListView(),
        ],
      );
    }

  }

  getLocation(String text) async {
    String apiURL =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}&language=${widget.language}";

    if (widget.countries != null) {
      // in

      for (int i = 0; i < widget.countries!.length; i++) {
        String country = widget.countries![i];

        if (i == 0) {
          apiURL = apiURL + "&components=country:$country";
        } else {
          apiURL = apiURL + "|" + "country:" + country;
        }
      }
    }
    if (widget.placeType != null) {
      apiURL += "&types=${widget.placeType?.apiString}";
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }

    print("urlll $apiURL");
    try {
      String proxyURL = "https://cors-anywhere.herokuapp.com/";
      String url = kIsWeb ? proxyURL + apiURL : apiURL;

      /// Add the custom header to the options
      final options = kIsWeb
          ? Options(headers: {"x-requested-with": "XMLHttpRequest"})
          : null;
      Response response = await _dio.get(url);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      if (text.length == 0) {
        alPredictions.clear();
        this._overlayEntry?.remove();
        return;
      }

      isSearched = false;
      alPredictions.clear();
      if (subscriptionResponse.predictions!.length > 0 &&
          (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        alPredictions.addAll(subscriptionResponse.predictions!);
        setState(() {

        });
      }

      if (widget.useOverlay) {
        this._overlayEntry = null;
        this._overlayEntry = this._createOverlayEntry();
        Overlay.of(context)!.insert(this._overlayEntry!);
      }
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  @override
  void initState() {
    super.initState();
    sutUpStateController();
    _dio = Dio();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);
  }

  void sutUpStateController() {
    if(widget.stateController!=null){
      widget.stateController = this;
    }
  }

  textChanged(String text) async {
    getLocation(text);
  }

  OverlayEntry? _createOverlayEntry() {
    if (context != null && context.findRenderObject() != null) {
      RenderBox renderBox = context.findRenderObject() as RenderBox;
      var size = renderBox.size;
      var offset = renderBox.localToGlobal(Offset.zero);
      return OverlayEntry(
          builder: (context) => Positioned(
                left: offset.dx,
                top: size.height + offset.dy,
                width: size.width,
                child: CompositedTransformFollower(
                  showWhenUnlinked: false,
                  link: this._layerLink,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                      child: buildListView(),),
                ),
              ));
    }
  }

  ListView buildListView() {
    return ListView.separated(
                  padding: widget.listPadding,
                  shrinkWrap: true,
                  physics: widget.physics,
                  itemCount: alPredictions.length,
                  separatorBuilder: (context, pos) =>
                      widget.seperatedBuilder ?? SizedBox(),
                  itemBuilder: (BuildContext context, int index) {
                    return InkWell(
                      onTap: () {
                        var selectedData = alPredictions[index];
                        if (index < alPredictions.length) {
                          widget.itemClick!(selectedData);

                          if (widget.isLatLngRequired) {
                            getPlaceDetailsFromPlaceId(selectedData);
                          }
                          if (widget.useOverlay) {
                            removeOverlay();
                          }else{
                            alPredictions.clear();
                            setState(() {});
                          }
                          widget.focusNode?.unfocus();
                        }
                      },
                      child: widget.itemBuilder != null
                          ? widget.itemBuilder!(
                              context, index, alPredictions[index])
                          : Container(
                              padding: EdgeInsets.all(10),
                              child: Text(alPredictions[index].description!)),
                    );
                  },
                );
  }

  removeOverlay() {
    alPredictions.clear();
    this._overlayEntry = this._createOverlayEntry();
    if (context != null) {
      Overlay.of(context).insert(this._overlayEntry!);
      this._overlayEntry!.markNeedsBuild();
    }
  }

  Future<Response?> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    //String key = GlobalConfiguration().getString('google_maps_key');

    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    try {
      Response response = await _dio.get(
        url,
      );

      PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

      prediction.lat = placeDetails.result!.geometry!.location!.lat.toString();
      prediction.lng = placeDetails.result!.geometry!.location!.lng.toString();

      widget.getPlaceDetailWithLatLng!(prediction);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  void clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    setState(() {
      alPredictions.clear();
      isCrossBtn = false;
    });

    if (this._overlayEntry != null) {
      try {
        this._overlayEntry?.remove();
      } catch (e) {}
    }
  }

  _showCrossIconWidget() {
    return (widget.textEditingController.text.isNotEmpty);
  }

  _showSnackBar(String errorData) {
    if (widget.showError) {
      final snackBar = SnackBar(
        content: Text("$errorData"),
      );

      // Find the ScaffoldMessenger in the widget tree
      // and use it to show a SnackBar.
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(
      responseBody as Map<String, dynamic>);
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng = void Function(
    Prediction postalCodeResponse);

typedef ListItemBuilder = Widget Function(
    BuildContext context, int index, Prediction prediction);
