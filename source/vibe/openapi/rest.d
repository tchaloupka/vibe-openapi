module vibe.openapi.rest;

import std.stdio;
import std.string;
import std.traits;
import vibe.openapi.definitions;
import vibe.web.internal.rest.common;
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
	import std.algorithm : filter, map, all;
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
		{
			doc.registerRestInterface!(R.Interface)(intf.subInterfaces[i].settings);
		}
		else
		{
			doc.registerRestInterface!R(intf.subInterfaces[i].settings);
		}
	}

	// handle REST API functions
	foreach (i, func; intf.RouteFunctions)
	{
		auto route = intf.routes[i];
		auto diagparams = route.parameters.filter!(p => p.kind != ParameterKind.internal).map!(p => p.fieldName).array;
		writefln("REST route: %s %s %s", route.method, route.pattern, diagparams);
		//router.match(route.method, route.fullPattern, handler);
	}

	return doc;
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

	writeln(doc.serializeToJsonString);
}
