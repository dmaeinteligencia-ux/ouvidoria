// Mapa base dos painéis e do cadastro de bairros: OpenStreetMap, sem chave de acesso.
// O Leaflet só existe no navegador, então é carregado sob demanda nos componentes .client.
export const CENTRO_UBERLANDIA: [number, number] = [-18.9186, -48.2772]
export const ZOOM_CIDADE = 12
export const LIMITES_MUNICIPIO: [[number, number], [number, number]] = [[-19.60, -48.95], [-18.40, -47.60]]
export const CAMADA_OSM = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
export const ATRIBUICAO_OSM = '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>'

export interface PosicaoBairro { id: number, nome: string, latitude: number | null, longitude: number | null }

export async function carregarLeaflet() {
  const [L] = await Promise.all([import('leaflet'), import('leaflet/dist/leaflet.css')])
  return L.default ?? L
}

// Mapa já com a camada do OpenStreetMap, preso ao município.
export async function criarMapa(elemento: HTMLElement) {
  const L = await carregarLeaflet()
  const mapa = L.map(elemento, {
    center: CENTRO_UBERLANDIA,
    zoom: ZOOM_CIDADE,
    minZoom: 10,
    maxBounds: L.latLngBounds(LIMITES_MUNICIPIO).pad(0.2),
  })
  L.tileLayer(CAMADA_OSM, { maxZoom: 18, attribution: ATRIBUICAO_OSM }).addTo(mapa)
  mapa.attributionControl.setPrefix(false)
  return { L, mapa }
}

// Bolha com área proporcional à quantidade.
export function raioBolha(n: number, maximo: number, maior = 26, menor = 4): number {
  if (!n || !maximo) return 0
  return Math.max(menor, Math.sqrt(n / maximo) * maior)
}
