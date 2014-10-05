#version 120

// input

varying vec2 f_texcoord;
varying vec3 normal;

uniform sampler2D mytexture;
uniform int has_texture;
uniform int has_lighting;

uniform vec4 camera;
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

// structures

struct lightSource
{
  vec4 position;
  vec4 diffuse;
  vec4 ambient;
  vec4 specular;
};

struct material
{
  vec4 diffuse;
  vec4 ambient;
  vec4 specular;
  float shininess;
};

// defaults

lightSource light1 = lightSource(
  vec4(20, 5, 20, 0),              // position
  vec4(0.8, 0.8, 0.8, 0),          // diffuse
  vec4(0.1, 0.1, 0.1, 0),          // ambient
  vec4(0.8, 0.8, 0.8, 1)           // specular
);

material frontMaterial = material(
  vec4(0.75, 0.75, 0.75, 0),        // diffuse
  vec4(0.75, 0.75, 0.75, 0),        // ambient
  vec4(0.2, 0.2, 0.2, 1),           // specular
  510.0                             // shininess
);

uniform vec4 default_color = vec4(0.8, 0.8, 0.8, 1);
uniform vec4 global_ambient = vec4(0.2, 0.2, 0.2, 1); // yellow abmient

// functions

vec4 compute_color(vec4 initial_color) {
  if(has_lighting == 0) return initial_color;
  vec4 light_dir = normalize(light1.position);
  vec3 light_dir3 = vec3(light_dir.x, light_dir.y, light_dir.z);
  vec3 N = normalize(normal);
  float intensity = max(dot(N, light_dir3), 0);

  vec4 diffuse = frontMaterial.diffuse * light1.diffuse;
  vec4 ambient = frontMaterial.ambient * (light1.ambient + global_ambient);

  vec4 specular = vec4(0.0);

  if (intensity > 0.0) {
    vec4 eye = -1 * camera;
    vec4 eye_shifted = transpose (inverse( view * model)) * eye;
    vec4 halfway = normalize( eye - light_dir );
    float NdotHV = max(dot(vec4(N, 0.0), halfway),0.0);
    specular = light1.specular * frontMaterial.specular * pow(NdotHV, frontMaterial.shininess);
  }

  vec4 result = initial_color * (intensity * diffuse + ambient) + specular;
  return result;
}

//main

void main(void) {
  vec4 color;
  if(has_texture > 0) {
    color = texture2D(mytexture, f_texcoord);
  } else {
    color = default_color;
  }
  gl_FragColor = compute_color(color);
}