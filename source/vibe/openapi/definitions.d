module vibe.openapi.definitions;

import vibe.data.serialization;

/// This is the root document object of the OpenAPI document.
struct Document
{
	/// This string MUST be the semantic version number of the OpenAPI Specification version that
	/// the OpenAPI document uses. The openapi field SHOULD be used by tooling specifications and
	/// clients to interpret the OpenAPI document. This is not related to the API info.version
	/// string.
	string openapi = "3.0.2";

	/// Provides metadata about the API. The metadata MAY be used by tooling as required.
	Info info;

	/// An array of Server Objects, which provide connectivity information to a target server. If
	/// the servers property is not provided, or is an empty array, the default value would be a
	/// Server Object with a url value of /.
	@optional Server[] servers;

	/// The available paths and operations for the API.
	/// A relative path to an individual endpoint. The field name MUST begin with a slash. The path
	/// is appended (no relative URL resolution) to the expanded URL from the Server Object's url
	/// field in order to construct the full URL. Path templating is allowed. When matching URLs,
	/// concrete (non-templated) paths would be matched before their templated counterparts.
	/// Templated paths with the same hierarchy but different templated names MUST NOT exist as they
	/// are identical. In case of ambiguous matching, it's up to the tooling to decide which one to
	/// use.
	Path[string] paths;

	/// An element to hold various schemas for the specification.
	@optional Components components;

	/// A declaration of which security mechanisms can be used across the API. The list of values
	/// includes alternative security requirement objects that can be used. Only one of the security
	/// requirement objects need to be satisfied to authorize a request. Individual operations can
	/// override this definition.
	@optional SecurityRequirement[] security;

	/// A list of tags used by the specification with additional metadata. The order of the tags can
	/// be used to reflect on their order by the parsing tools. Not all tags that are used by the
	/// Operation Object must be declared. The tags that are not declared MAY be organized randomly
	/// or based on the tools' logic. Each tag name in the list MUST be unique.
	@optional Tag[] tags;

	/// Additional external documentation.
	@optional ExternalDocumentation externalDocs;
}

/// The object provides metadata about the API. The metadata MAY be used by the clients if needed,
/// and MAY be presented in editing or documentation generation tools for convenience.
struct Info
{
	/// The title of the application.
	string title;

	/// A short description of the application. CommonMark syntax MAY be used for rich text
	/// representation.
	@optional string description;

	/// A URL to the Terms of Service for the API. MUST be in the format of a URL.
	@optional string termsOfService;

	/// The contact information for the exposed API.
	@optional Contact contact;

	/// The license information for the exposed API.
	@optional License license;

	/// The version of the OpenApi document (which is distinct from the OpenApi Specification
	/// version or the API implementation version).
	string version_;
}

struct Contact
{
	//TODO: https://swagger.io/specification/#contactObject
}

struct License
{
	//TODO: https://swagger.io/specification/#licenseObject
}

/// An object representing a Server.
struct Server
{
	/// A URL to the target host. This URL supports Server Variables and MAY be relative, to
	/// indicate that the host location is relative to the location where the OpenAPI document is
	/// being served. Variable substitutions will be made when a variable is named in {brackets}.
	string url;

	/// An optional string describing the host designated by the URL. CommonMark syntax MAY be used
	/// for rich text representation.
	@optional string description;

	/// A map between a variable name and its value. The value is used for substitution in the
	/// server's URL template.
	@optional ServerVariable[string] variables;
}

/// An object representing a Server Variable for server URL template substitution.
struct ServerVariable
{
	//TODO: https://swagger.io/specification/#serverVariableObject
}

/// Describes the operations available on a single path. A Path Item MAY be empty, due to ACL
/// constraints. The path itself is still exposed to the documentation viewer but they will not know
/// which operations and parameters are available.
struct Path
{
	@optional:

	/// Allows for an external definition of this path item. The referenced structure MUST be in the
	/// format of a Path Item Object. If there are conflicts between the referenced definition and
	/// this Path Item's definition, the behavior is undefined.
	@name("$ref") string _ref;

	/// An optional, string summary, intended to apply to all operations in this path.
	string summary;

	/// An optional, string description, intended to apply to all operations in this path.
	/// CommonMark syntax MAY be used for rich text representation.
	string description;

	/// A definition of a GET operation on this path.
	Operation get;

	/// A definition of a PUT operation on this path.
	Operation put;

	/// A definition of a POST operation on this path.
	Operation post;

	/// A definition of a DELETE operation on this path.
	Operation delete_;

	/// A definition of a OPTIONS operation on this path.
	Operation options;

	/// A definition of a HEAD operation on this path.
	Operation head;

	/// A definition of a PATCH operation on this path.
	Operation patch;

	/// A definition of a TRACE operation on this path.
	Operation trace;

	/// An alternative server array to service all operations in this path.
	Server[] servers;

	/// A list of parameters that are applicable for all the operations described under this path.
	/// These parameters can be overridden at the operation level, but cannot be removed there. The
	/// list MUST NOT include duplicated parameters. A unique parameter is defined by a combination
	/// of a name and location. The list can use the Reference Object to link to parameters that are
	/// defined at the OpenApi Object's components/parameters.
	//TOOD: ParameterObject | ReferenceObject - https://swagger.io/specification/#pathItemObject
	Parameter[] parameters;
}

/// Describes a single API operation on a path.
struct Operation
{
	/// The list of possible responses as they are returned from executing this operation.
	///
	/// "default" - The documentation of responses other than the ones declared for specific HTTP
	/// response codes. Use this field to cover undeclared responses. A Reference Object can link to
	/// a response that the OpenAPI Object's components/responses section defines.
	///
	/// "status code" - Any HTTP status code can be used as the property name, but only one property
	/// per code, to describe the expected response for that HTTP status code. A Reference Object
	/// can link to a response that is defined in the OpenAPI Object's components/responses section.
	/// This field MUST be enclosed in quotation marks (for example, "200") for compatibility
	/// between JSON and YAML. To define a range of response codes, this field MAY contain the
	/// uppercase wildcard character X. For example, 2XX represents all response codes between
	/// [200-299]. Only the following range definitions are allowed: 1XX, 2XX, 3XX, 4XX, and 5XX. If
	/// a response is defined using an explicit code, the explicit code definition takes precedence
	/// over the range definition for that code.
	Response[string] responses;

	@optional:

	/// A list of tags for API documentation control. Tags can be used for logical grouping of
	/// operations by resources or any other qualifier.
	string[] tags;

	/// A short summary of what the operation does.
	string summary;

	/// A verbose explanation of the operation behavior. CommonMark syntax MAY be used for rich text
	/// representation.
	string description;

	/// Additional external documentation for this operation.
	ExternalDocumentation externalDocs;

	/// Unique string used to identify the operation. The id MUST be unique among all operations
	/// described in the API. Tools and libraries MAY use the operationId to uniquely identify an
	/// operation, therefore, it is RECOMMENDED to follow common programming naming conventions.
	string operationId;

	/// A list of parameters that are applicable for this operation. If a parameter is already
	/// defined at the Path Item, the new definition will override it but can never remove it. The
	/// list MUST NOT include duplicated parameters. A unique parameter is defined by a combination
	/// of a name and location. The list can use the Reference Object to link to parameters that are
	/// defined at the OpenApi Object's components/parameters.
	Parameter[] parameters;

	/// The request body applicable for this operation. The requestBody is only supported in HTTP
	/// methods where the HTTP 1.1 specification RFC7231 has explicitly defined semantics for
	/// request bodies. In other cases where the HTTP spec is vague, requestBody SHALL be ignored by
	/// consumers.
	RequestBody requestBody;

	/// A map of possible out-of band callbacks related to the parent operation. The key is a unique
	/// identifier for the Callback Object. Each value in the map is a Callback Object that
	/// describes a request that may be initiated by the API provider and the expected responses.
	/// The key value used to identify the callback object is an expression, evaluated at runtime,
	/// that identifies a URL to use for the callback operation.
	Callback[string] callbacks;

	/// Declares this operation to be deprecated. Consumers SHOULD refrain from usage of the
	/// declared operation. Default value is false.
	bool deprecated_;

	/// A declaration of which security mechanisms can be used for this operation. The list of
	/// values includes alternative security requirement objects that can be used. Only one of the
	/// security requirement objects need to be satisfied to authorize a request. This definition
	/// overrides any declared top-level security. To remove a top-level security declaration, an
	/// empty array can be used.
	SecurityRequirement[] security;

	/// An alternative server array to service this operation. If an alternative server object is
	/// specified at the Path Item Object or Root level, it will be overridden by this value.
	Server[] servers;
}

/// Describes a single operation parameter.
///
/// A unique parameter is defined by a combination of a name and location.
/// Parameter Locations
///
/// There are four possible parameter locations specified by the in field:
///
///   * path - Used together with Path Templating, where the parameter value is actually part of the operation's URL. This does not include the host or base path of the API. For example, in /items/{itemId}, the path parameter is itemId.
///   * query - Parameters that are appended to the URL. For example, in /items?id=###, the query parameter is id.
///   * header - Custom headers that are expected as part of the request. Note that RFC7230 states header names are case insensitive.
///   * cookie - Used to pass a specific cookie value to the API.
struct Parameter
{
	/// The name of the parameter. Parameter names are case sensitive.
	///   * If in is "path", the name field MUST correspond to the associated path segment from the path field
	///     in the Paths Object. See Path Templating for further information.
	///   * If in is "header" and the name field is "Accept", "Content-Type" or "Authorization",
	///     the parameter definition SHALL be ignored.
	///   * For all other cases, the name corresponds to the parameter name used by the in property.
	string name;

	/// The location of the parameter.
	ParameterIn in_;

	mixin ParameterOptions;
}

/// Possible values for `Parameter.in_`
enum ParameterIn : string {
	query = "query", ///
	header = "header", ///
	path = "path", ///
	cookie = "cookie", ///
	body_ = "body" ///
}

// Common parameter options
mixin template ParameterOptions()
{
	@optional:

	/// A brief description of the parameter. This could contain examples of use. CommonMark syntax
	/// MAY be used for rich text representation.
	string description;

	/// Determines whether this parameter is mandatory. If the parameter location is "path", this
	/// property is REQUIRED and its value MUST be true. Otherwise, the property MAY be included and
	/// its default value is false.
	bool required;

	/// Specifies that a parameter is deprecated and SHOULD be transitioned out of usage.
	bool deprecated_;

	/// Sets the ability to pass empty-valued parameters. This is valid only for query parameters
	/// and allows sending a parameter with an empty value. Default value is false. If style is
	/// used, and if behavior is n/a (cannot be serialized), the value of allowEmptyValue SHALL be
	/// ignored. Use of this property is NOT RECOMMENDED, as it is likely to be removed in a later
	/// revision.
	bool allowEmptyValue;

	/// Describes how the parameter value will be serialized depending on the type of the parameter
	/// value. Default values (based on value of in): for query - form; for path - simple; for
	/// header - simple; for cookie - form.
	Style style;

	/// When this is true, parameter values of type array or object generate separate parameters for
	/// each value of the array or key-value pair of the map. For other types of parameters this
	/// property has no effect. When style is form, the default value is true. For all other styles,
	/// the default value is false.
	bool explode;

	/// Determines whether the parameter value SHOULD allow reserved characters, as defined by
	/// RFC3986 :/?#[]@!$&'()*+,;= to be included without percent-encoding. This property only
	/// applies to parameters with an in value of query. The default value is false.
	bool allowReserved;

	/// The schema defining the type used for the parameter.
	Schema schema;

	/// Example of the media type. The example SHOULD match the specified schema and encoding
	/// properties if present. The example field is mutually exclusive of the examples field.
	/// Furthermore, if referencing a schema which contains an example, the example value SHALL
	/// override the example provided by the schema. To represent examples of media types that
	/// cannot naturally be represented in JSON or YAML, a string value can contain the example with
	/// escaping where necessary.
	string example;

	/// Examples of the media type. Each example SHOULD contain a value in the correct format as
	/// specified in the parameter encoding. The examples field is mutually exclusive of the example
	/// field. Furthermore, if referencing a schema which contains an example, the examples value
	/// SHALL override the example provided by the schema.
	Example[] examples;

	/// A map containing the representations for the parameter. The key is the media type and the
	/// value describes it. The map MUST only contain one entry.
	MediaType[string] content;
}

/// Describes a single request body.
struct RequestBody
{
	/// The content of the request body. The key is a media type or media type range and the value
	/// describes it. For requests that match multiple keys, only the most specific key is
	/// applicable. e.g. text/plain overrides text/*
	MediaType[string] content;

	@optional:

	/// A brief description of the request body. This could contain examples of use. CommonMark
	/// syntax MAY be used for rich text representation.
	string description;

	/// Determines if the request body is required in the request. Defaults to false.
	bool required;
}

/// Each Media Type Object provides schema and examples for the media type identified by its key.
struct MediaType
{
	@optional:

	/// The schema defining the type used for the request body.
	Schema schema;

	/// Example of the media type. The example object SHOULD be in the correct format as specified
	/// by the media type. The example field is mutually exclusive of the examples field.
	/// Furthermore, if referencing a schema which contains an example, the example value SHALL
	/// override the example provided by the schema.
	string example;

	/// Examples of the media type. Each example object SHOULD match the media type and specified
	/// schema if present. The examples field is mutually exclusive of the example field.
	/// Furthermore, if referencing a schema which contains an example, the examples value SHALL
	/// override the example provided by the schema.
	Example[string] examples;

	/// A map between a property name and its encoding information. The key, being the property
	/// name, MUST exist in the schema as a property. The encoding object SHALL only apply to
	/// requestBody objects when the media type is multipart or application/x-www-form-urlencoded.
	Encoding[string] encoding;
}

/// A map of possible out-of band callbacks related to the parent operation. Each value in the map
/// is a Path Item Object that describes a set of requests that may be initiated by the API provider
/// and the expected responses. The key value used to identify the callback object is an expression,
/// evaluated at runtime, that identifies a URL to use for the callback operation.
alias Callback = Path[string];

/// In order to support common ways of serializing simple parameters, a set of style values are defined.
enum Style : string
{
	undefined = "", ///

	/// Path-style parameters defined by RFC6570
	matrix = "matrix",

	/// Label style parameters defined by RFC6570
	label = "label",

	/// Form style parameters defined by RFC6570. This option replaces collectionFormat with a csv
	/// (when explode is false) or multi (when explode is true) value from OpenApi 2.0.
	form = "form",

	/// Simple style parameters defined by RFC6570. This option replaces collectionFormat with a csv
	/// value from OpenApi 2.0.
	simple = "simple",

	/// Space separated array values. This option replaces collectionFormat equal to ssv from
	/// OpenApi 2.0.
	spaceDelimited = "spaceDelimited",

	/// Pipe separated array values. This option replaces collectionFormat equal to pipes from
	/// OpenApi 2.0.
	pipeDelimited = "pipeDelimited",

	/// Provides a simple way of rendering nested objects using form parameters.
	deepObject = "deepObject"
}

struct Example
{
	//TODO: https://swagger.io/specification/#exampleObject
}

/// A single encoding definition applied to a single schema property.
struct Encoding
{
	//TODO: https://swagger.io/specification/#encodingObject
}

struct Response
{
	//TODO: https://swagger.io/specification/#responseObject
}

struct Components
{
	//TODO: https://swagger.io/specification/#componentsObject
}

struct SecurityRequirement
{
	//TODO: https://swagger.io/specification/#securityRequirementObject
}

struct Tag
{
	//TODO: https://swagger.io/specification/#tagObject
}

struct ExternalDocumentation
{
	//TODO: https://swagger.io/specification/#externalDocumentationObject
}

class Schema
{
	//TODO: https://swagger.io/specification/#schemaObject
}