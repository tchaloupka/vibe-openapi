module vibe.openapi.rest;

import std.experimental.logger;
import std.stdio;
import std.string;
import std.traits;
import vibe.http.common : HTTPMethod;
import vibe.openapi.definitions;
import vibe.web.internal.rest.common : RestInterface, Route;
import vibe.web.rest;

@safe:

/++
	Generate OpenApi specification from the REST interface.
	It works the same way as `URLRouter.registerRestInterface`, but instead of registering handlers to the `URLRouter`,
	it adds methods specification to the OpenApi document from the rest api definition.

	Template_Params:
		TImpl =	Either an interface type, or a class that derives from an interface.
				If the class derives from multiple interfaces, the first one will be assumed to be the API
				description and a warning will be issued.

	Params:
		instance = Server instance to use
		settings = Additional settings, such as the `MethodStyle` or the prefix
+/
ref Document registerRestInterface(TImpl)(ref Document doc, RestInterfaceSettings settings = null)
{
	import std.algorithm : among, filter, map, all;
	import std.array : array;
	import std.range : front;
	import vibe.web.internal.rest.common : ParameterKind;

	auto intf = RestInterface!TImpl(settings, false);

	// set base URL
	if (doc.servers is null) doc.servers ~= Server(intf.baseURL.stripRight("/"));

	// handle optional sub interfaces
	foreach (i, ovrld; intf.SubInterfaceFunctions)
	{
		enum fname = __traits(identifier, intf.SubInterfaceFunctions[i]);
		alias R = ReturnType!ovrld;

		static if (isInstanceOf!(Collection, R))
			doc.registerRestInterface!(R.Interface)(intf.subInterfaces[i].settings);
		else
			doc.registerRestInterface!R(intf.subInterfaces[i].settings);
	}

	// handle REST API functions
	foreach (i, func; intf.RouteFunctions)
	{
		auto route = intf.routes[i];
		auto diagparams = route.parameters.filter!(p => p.kind != ParameterKind.internal).map!(p => p.fieldName).array;

		string pathPattern = route.pattern;
		//TODO: convert to openapi format

		infof("REST route: %s %s %s", route.method, pathPattern, diagparams);

		auto ppath = pathPattern in doc.paths;
		if (ppath is null)
		{
			doc.paths[pathPattern] = Path();
			ppath = pathPattern in doc.paths;
		}

		with (HTTPMethod)
		if (!route.method.among(GET, PUT, POST, DELETE, OPTIONS, HEAD, PATCH, TRACE))
		{
			warningf("'%s' isn't supported in OpenApi specification, function '%' won't be described", route.method, route.functionName);
			continue;
		}

		if (!areEqual((*ppath)[route.method], Operation.init))
		{
			warningf("'%s %s' already set, function '%' won't be described", route.method, pathPattern, route.functionName);
			continue;
		}

		(*ppath)[route.method] = route.describeOperation();
	}

	return doc;
}

private Operation describeOperation(in Route route)
{
	Operation op;
	op.operationId = route.functionName;
	return op;
}

@("Test simple API")
unittest
{
	import vibe.openapi.data.json;

	@path("/api/")
	interface APIRoot {
		string get();
	}

	Document doc;
	doc.registerRestInterface!APIRoot();
	assert(doc.servers.length == 1);
	assert(doc.servers[0].url == "http://localhost/api");

	Parameter param;
	param.schema = new Schema();
	param.schema._ref = "fooref";
	doc.paths["/"].get.parameters ~= param;

	info(doc.serializeToJsonString);
}
