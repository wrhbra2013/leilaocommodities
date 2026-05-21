export async function cotacoesRoutes(fastify) {
  fastify.get('/api/cotacoes', async (req, reply) => {
    const mock = {
      soja: { preco: 138.50, variacao: '+2.30', data: new Date().toISOString().split('T')[0] },
      milho: { preco: 62.80, variacao: '-0.75', data: new Date().toISOString().split('T')[0] },
      'cafe-arabica': { preco: 245.90, variacao: '+5.10', data: new Date().toISOString().split('T')[0] },
      'boi-gordo': { preco: 310.00, variacao: '+1.50', data: new Date().toISOString().split('T')[0] },
      'acucar-cristal': { preco: 85.20, variacao: '-1.20', data: new Date().toISOString().split('T')[0] },
      algodao: { preco: 112.40, variacao: '+0.80', data: new Date().toISOString().split('T')[0] },
      'petroleo-brent': { preco: 82.15, variacao: '-1.45', data: new Date().toISOString().split('T')[0] },
      ouro: { preco: 345.60, variacao: '+3.20', data: new Date().toISOString().split('T')[0] },
    };
    const { comodities: slugs } = req.query;
    if (slugs) return slugs.split(',').reduce((acc, s) => { if (mock[s]) acc[s] = mock[s]; return acc; }, {});
    return mock;
  });
}
