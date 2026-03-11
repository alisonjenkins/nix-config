exports.handler = async (event) => {
  const name = event.name || "world";
  return {
    message: `Hello, ${name}!`,
  };
};
